#!/usr/bin/luajit

local server = { }

pcall(require, 'devel')

local  insert		=  table.insert
local  remove		=  table.remove

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  new		=  ffi.new
local bit		= require('bit')
local  band		=  bit.band

			  require('posix.errno')
			  require('posix.time')
			  require('posix.signal')

local class		= require('useful.class')
local  Class		=  class.Class
local fs		= require('useful.filesystem')
local dom		= require('useful.http.dom')
local path		= require('useful.path')
local mime		= require('useful.http.mime')
local status		= require('useful.http.status')
local  Status		=  status.Status
local  BAD_REQUEST	=  status.BAD_REQUEST
local  NOT_FOUND	=  status.NOT_FOUND
local  OK		=  status.OK
local range		= require('useful.range')
local rstring		= require('useful.range.string')
local  make_until	=  rstring.make_until
local  DOT		=  rstring.DOT
local  QUESTION		=  rstring.QUESTION
local  AMP		=  rstring.AMP
--local  rstrip		=  rstring.rstrip
--local  skip_ws		=  rstring.skip_ws
local poll		= require('useful.scheduler.poll')
local protect		= require('useful.protect')
local socket		= require('useful.scheduler.socket')
local  TCPServer	=  socket.TCPServer
local socket_		= require('useful.socket')
local  addr_to_ip_port	=  socket_.addr_to_ip_port
local stdio		= require('useful.stdio')
local  printf		=  stdio.printf
local  sprintf		=  stdio.sprintf
local system		= require('useful.system')
local  is_main		=  system.is_main
local time		= require('useful.time')

local do_status		= make_until(rstring.SPACE)
local do_path		= make_until(rstring.SLASH, rstring.QUESTION)
local do_args		= make_until(rstring.AMP, rstring.EQUALS)

local empty		= range.char(nil, nil)

local MAXENTRIES	= status.MAXENTRIES

print('startup mem=', collectgarbage('count')*1024)

-- ignore stupid socket SIGPIPE signals (i which this was a setsockopt())
C.signal(C.SIGPIPE, cast('sighandler_t', C.SIG_IGN))

protect.error_ = function(msg)
	if msg:find('closed') == nil then
		error(msg..'\n'..debug.traceback())
	else
		error(msg)
	end
end

local Request	= Class(Status, {})
server.Request	= Request

function Request:new(size)
	Status.new(self, size)
	self.dentries	= status.char_range_array(MAXENTRIES)
	self.args	= status.char_range_array(MAXENTRIES)
	self.time	= time.now()
	self.path	= self.dentries[0]
end

function Request:setup(sock)
	Status.setup(self, sock)
	self.method	= empty
	self.uri	= empty
	self.protocol	= empty
	self.path	= empty

	self.ndentries	= 0
	self.nargs	= 0
end

function Request:process_path(path)		--luacheck:ignore
	self.path	= path
	path		= self.path:save()
	local dentries	= self.dentries
	local ndentries = 0

	local function is_dot(dentry)
		if dentry:get_front() ~= DOT or dentry:size() > 2 then
			return false
		end
		if dentry:size() == 2 and dentry.front[1] ~= DOT then
			return false
		end
		return true
	end
	local function handle_dot(dentry)
		if dentry.front[1] == DOT then
			-- '..' removes previous dentry
			if ndentries > 0 then
				ndentries = ndentries - 1
			end
		end
		-- ignore '.' dentry
	end

	local dentry, found
	while ndentries < MAXENTRIES and not path:empty() do
		dentry, found = do_path(path)
		if dentry:empty() then --luacheck:ignore
			-- ignore empty dentry
		elseif is_dot(dentry) then
			handle_dot(dentry)
		else
			dentries[ndentries] = dentry
			ndentries = ndentries + 1
		end
		if found == QUESTION then
			self.path.back = dentry.back
			break
		end
	end

	self.ndentries = ndentries

	return path
end

function Request:process_args(args_range)
	-- args becomes [ name, value, ..., name, value ]
	-- value is empty when no '=value'
	local args	= self.args
	local nargs	= 0
	local prev	= AMP
	local found
	while nargs < MAXENTRIES and not args_range:empty() do
		args[nargs], found	= do_args(args_range)
		nargs			= nargs + 1
		if prev == AMP and found == AMP then
			args[nargs].front	= nil
			args[nargs].back	= nil
			nargs			= nargs + 1
		end
		prev			= found
	end
	if nargs < MAXENTRIES and band(nargs, 2) ~= 0 then
		args[nargs].front	= nil
		args[nargs].back	= nil
		nargs			= nargs + 1
	end
	self.nargs	= nargs
end

function Request:recv_status()
	self.time	= time.now()
	Status.recv_status(self)
	local status	= self.status:save()
	self.method	= do_status(status)
	self.uri	= do_status(status)
	self.protocol	= do_status(status)
	local args	= self:process_path(self.uri:save())
	self:process_args(args)
end

local RFC1123FMT	= '%a, %d %b %Y %H:%M:%S GMT'

local Response	= Class(Status, {})
server.Response	= Response
function Response:default_header()
	self:set('Server', 'server.lua')
	self:set('Connection', 'close')
	local buf	= new('char[256]')
	local ta	= new('int64_t[1]')
	C.time(ta)
	local rc	= C.strftime(buf, 256, RFC1123FMT, C.gmtime(ta))
	self:set('Date', ffi.string(buf, rc))
end

function Response:response(code, contents)
	self:default_header()
	code = code or OK
	if contents then
		self:set('Content-Length', tostring(#contents))
	end
	self:send_response(code)
	if contents then
		self.sock:send(contents, #contents)
	end
end

local Transaction	= Class({})
server.Transaction	= Transaction

function Transaction:new(size)
	self.request	= Request(size)
	self.response	= Response(size)
	self.keep_alive	= 1

	self.notfound	= dom.document('html', 'en')
	self.notfound.html:add(dom.head(
		dom.title('MESSAGE'),
		dom.body(dom.h3('MESSAGE'))
	))
	self.notfound = tostring(self.notfound)

	--self.connect_time	= nil
	--self.addr		= nil
	self.working		= false
	self.num_connects	= 0
	self.num_requests	= 0
	self.time		= 0
end

function Transaction:setup(sock)
	self.sock = sock
	self.request:setup(self.sock)
	self.response:setup(self.sock)
end

function Transaction:get(name, default)
	return self.request:get(name, default)
end

function Transaction:get_number(name, default)
	return tonumber(self:get(name, default or 0))
end

function Transaction:handle_accept()
	self.accepts = self:get('Accept')
end

function Transaction:handle_keep_alive()
	local connection = self:get('Connection')

	self.keep_alive = 1
	if connection ~= 'keep-alive' then
		self.keep_alive = 0
	end
	if self.keep_alive > 0 then
		self.response:set('Keep-Alive', self.keep_alive)
	end
end

function Transaction:dump_request()
	local request = self.request
	request:dump()
end

function Transaction:handle_path(name)
	local response	= self.response
	response:default_header()
	if name == '/' then
		name = '/index.html'
	end
	local full_path	= response.sock.root .. name
	local f = io.open(full_path)
	if f == nil then
		local s = name .. ' not found'
		s = self.notfound:gsub('MESSAGE', s)

		response:set('Content-Type', 'text/html')
		response:response(NOT_FOUND, s)
		return
	end
	local size	= fs.attributes(full_path, 'size')
	response:set('Content-Length', size)
	local _,ext	= path.split_ext(name)
	response:set('Content-Type', mime.exts[ext] or
				'application/unknown')
	response:send_response(OK)
	local s		= f:read(1024)
	while s ~= nil do
		response.sock:send(s, #s)
		s = f:read(1024)
	end
end

function Transaction:status()
	local response	= self.response
	response:default_header()
	local lines	= { }
	local line
	line = sprintf('%2s %8s %8s %6s/%6s %5s %-15s %-7s %s',
		'id', 'open sec', 'xact sec', 'con', 'req',
		'port', 'client ip', 'state', 'url')
	insert(lines, line)
	local now = time.now()
	for i,xact in ipairs(self.server.xacts) do
		local request = xact.request
		local uri = ''
		if request.uri ~= nil and request.uri.front ~= nil then
			uri = xact.request.uri.s
		end
		local ip, port
		if xact.addr then
			ip, port = addr_to_ip_port(xact.addr)
		else
			ip, port = '', 0
		end
		local connect_time
		if xact.connect_time then
			connect_time = time.dt(now, xact.connect_time)
		else
			connect_time = 0
		end

		line = sprintf('%2d %8.3f %8.3f %6d/%6d %5d %-15s %-7s %s', i,
				connect_time,
				xact.time,
				xact.num_connects,
				xact.num_requests,
				port,
				ip,
				xact.working and 'working' or 'idle',
				uri
			)
		insert(lines, line)
	end
	local s = table.concat(lines, '\n')..'\n'
	response:set('Content-Type', 'text/plain')
	response:response(OK, s)
end

function Transaction:hook()
	local request	= self.request
	local response	= self.response
	local length	= tonumber(request:get('content-length', 0))
	printf('length=%d\n', length)
	local n		= 0
	local data	= { }
	while n < length do
		local s = request:read(length).s
		table.insert(data, s)
		n	= n + #s
	end
	data		= table.concat(data)
	local fout	= io.open('hookdata', 'w')
	fout:write(data)
	fout:close()
	--printf('data=<%s>\n', data)
	if request:get('content-type', '*/*') == 'application/json' then
		local json	= require('useful.json')
		local tables		= require('useful.tables')
		local  serialize	=  tables.serialize
		print(serialize(json.decode(data)))
		response:default_header()
		local s = [[
		this worked
]]
		response:set('Content-Type', 'text/plain')
		response:response(OK, s)
	else
		response:response(BAD_REQUEST, 'Only json content supported')
	end
end

function Transaction:handle()
	self:handle_accept()
	self:handle_keep_alive()
	local request = self.request
	--printf('%s %s %s\n', os.date(), request.method, request.uri)
	--[[
	TODO: add modular setup based on self.request.dentries[0]
		maybe a set of rewrite rules? this would happen before
		the modules get the request.
	]]--
	local s = request.path.s
	if s == '/status' then
		self:status()
	elseif s == '/hook' then
		self:hook()
	else
		self:handle_path(s)
	end
	--self:router(request, response)
end

function Transaction:process(sock)
	self.keep_alive	= 1
	sock.timeout	= self.keep_alive
	self:setup(sock)
	local start = time.now()
	repeat
		self.request:recv()
		self.num_requests = self.num_requests + 1
		--self:dump_request()
		print(self.request.status.s)
		self:handle()
	until self.keep_alive == 0
	self.time = time.dt(time.now(), start) * 1e3
end

local HTTPServer	= Class(TCPServer, { })
server.HTTPServer	= HTTPServer

function HTTPServer:new(port, root, options)
	options		= options or { max=16, }
	self.options	= options
	self.xacts	= { }
	self.xacts_idle	= { }
	self.root	= root
	for _=1,self.options.max do
		local xact	= Transaction(32768)
		xact.server	= self
		insert(self.xacts, xact)
		insert(self.xacts_idle, xact)
	end
	local client	= function(...)
		self:client(...)
	end
	TCPServer.new(self, port, client, options)
end

function HTTPServer:idle() -- luacheck:ignore
	collectgarbage()
end

function HTTPServer:client(sock, id, addr)
	--print('client start addr=', addr)
	local xact		= remove(self.xacts_idle, 1)
	xact.working		= true
	xact.connect_time	= time.now()
	xact.num_connects	= xact.num_connects + 1
	xact.addr		= addr
	local thread		= poll.thread()
	thread.error		= function(err)
		local closed 	= err:sub(-6)
		if closed ~= 'closed' then
			print('error: '..err)
		end
	end
	sock.id			= id
	sock.root		= self.root
	local ok, err = xpcall(function()
		xact:setup(sock)
		xact:process(sock)
	end, debug.traceback)
	sock:shutdown()
	xact.working = false
	insert(self.xacts_idle, xact)
	if not ok and not err:find('closed') and not err:find('timeout') then
		error(err)
	end
end

local function main(args)
	local port = tonumber(args[1] or '8089')
	print('listening on port '..port)
	local server_ = HTTPServer(port, arg[2] or '.', { max=8, })
	server_:run()
	print('server exitted')
end
server.main = main

if is_main() then
	main(arg)
else
	return server
end
