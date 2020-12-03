--
-- u s e f u l / s l o p . l u a
--
local slop = { }

local ffi	= require('ffi')
local  cast	=  ffi.cast
local  fstring	=  ffi.string
local  new	=  ffi.new


local class	= require('useful.class')
local Class	= class.Class
local strings	= require('useful.strings')
local  strip	=  strings.strip
local  split	=  strings.split
local  ljust	=  strings.ljust
		  require('useful.socket')
local stream	= require('useful.stream')
local system	= require('useful.system')
local  is_main	=  system.is_main
local  unpack	=  system.unpack
local tables	= require('useful.tables')

local  format	=  string.format

local  insert	=  table.insert
local  remove	=  table.remove
local  join	=  table.concat

local line_limit	= 256
local multi_limit	= 256
local binary_limit	= 1024 * 1024

local eol		= '\n'
local multi_start	= '<'
local multi_end		= '>'
local binary_start	= '['
local binary_end	= ']'
local error_start	= '?'

-- global commands
function slop.help(xact)
	local commands = xact.commands
	local cmds
	if #xact.args < 1 then
		cmds = tables.keys(commands)
		table.sort(cmds)
	else
		cmds = xact.args
	end
	local ls = tables.imap(cmds, function(_,c) return #c end)
	local ml = math.max(unpack(ls)) + 2
	local multi = {}
	for _,name in ipairs(cmds) do
		local cmd = commands[name]
		local usage
		if cmd == nil then
			usage = 'invalid command' + eol
		else
			usage = cmd.name .. ' ' .. cmd.usage
		end
		local s = ljust(name .. ': ', ml) ..  strip(usage)
		insert(multi, s)
	end
	return xact:send_multi(join(xact.args, ' '), multi)
end

function slop.limits(xact)
	local s = string.format('%d %d %d', xact.line_limit,
			xact.multi_limit, xact.binary_limit)
	return xact:send_single(s)
end

slop.Command = Class({
	new = function(self, name, func, usage)
		self.name	= name
		self.func	= func
		self.usage	= usage
	end,
})

slop.Transaction = Class({
	new = function(self)
		self.done		= false
		self.commands		= {}
		self.line_limit		= line_limit
		self.multi_limit	= multi_limit
		self.binary_limit	= binary_limit
		self:reset()
	end,

	reset = function(self)
		self.name		= ''
		self.args		= {}
		self.seq		= nil
		self.binary		= nil
		self.multi		= {}
		self.error		= false
		self.valid		= true
		self.error_message	= ''
	end,

	add = function(self, name, func, usage)
		self.commands[name] = slop.Command(name, func, usage)
	end,

	write = function(self, data)
		self.out:write(cast('char *', data), #data)
	end,

	send = function(self, leader, message)
		local s = {}
		if self.error then insert(s, error_start) end
		if self.seq ~= nil then insert(s, self.seq) end
		if self.name then insert(s, self.name) end
		insert(s, message .. eol)
		self:write(leader .. join(s, ' '))
	end,

	finish = function(self, leader)
		if leader ~= '' then
			self:write(leader .. eol)
		end
		self.out:flush()
	end,

	send_single = function(self, message)
		self:send('', message)
		self:finish('')
		return 0
	end,

	send_multi = function(self, message, multi)
		self:send(multi_start, message)
		if #multi > 0 then
			-- TODO: multi_end at beginning of string needs to
			--       be escaped.
			self:write(join(multi, eol))
			self:write(eol)
		end
		self:finish(multi_end)
		return 0
	end,

	send_binary = function(self, message, binary)
		self:send(binary_start, #binary .. message)
		self:write(binary)
		self:finish(binary_end)
		return 0
	end,

	send_transaction = function(self, inp, out, request, data)
		self:reset()
		self.out = out
		if type(data) == 'table' then
			self:send_multi(request, data)
		elseif type(data) == 'string' then
			self:send_binary(request, data)
		else
			self:send_single(request)
		end
		return self:recv_transaction(inp)
	end,

	readline = function(self, inp) -- luacheck: ignore
		local rc
		local buf = new('char[?]', self.line_limit)
		rc = inp:readline(buf, self.line_limit)
		if rc <= 0 then
			return ''
		end
		if string.char(buf[rc-1]) ~= '\n' then
			return ''
		end
		return fstring(buf, rc)
	end,

	process_status = function(self)
		if #self.args < 1 then
			return
		end

		if self.args[1] == error_start then
			self.error = true
			remove(self.args, 1)
		end

		local arg = remove(self.args, 1)
		if arg == nil or #arg < 1 then
			return
		end
		local c = arg:sub(1,1):byte()
		if not (48 <= c and c <= 57) then -- '0' <= c <= '9'
			self.name = arg
		else
			self.seq = tonumber(arg)
			self.name = remove(self.args, 1)
		end
	end,

	recv_multi = function(self, inp)
		local line
		for _=1,self.multi_limit do
			-- TODO: multi_end at beginning of string needs to
			--       be escaped.
			line = self:readline(inp)
			if line:sub(1,#multi_end) == multi_end then
				break
			end
			-- remove newline and add it to the list
			insert(self.multi, line:sub(1,-2))
		end
		if line:sub(1,#multi_end) ~= multi_end then
			self.error_message = 'max line limit ' ..
						self.multi_limit
			self.valid = false
		end
	end,

	recv_binary = function(self, ssize, inp)
		self.valid = false
		local size = tonumber(ssize)
		if size == nil then
			self.error_message = 'bad size "' .. ssize .. '" format'
			return
		end
		if size > self.binary_limit then
			self.error_message = 'max binary size ' ..
						self.binary_limit
			return
		end

		self.binary = inp:read(size)

		local line = self:readline(inp)
		if not line:sub(1, #binary_end) ~= binary_end then
			self.error_message = 'no binary end'
		else
			self.valid = true
		end
	end,

	recv_transaction = function(self, inp)
		self:reset()
		self.status = self:readline(inp)
		if self.status == '' or
			self.status:sub(#self.status-(#eol-1)) ~= eol then
			return -1
		end
		self.args = split(strip(self.status), '%s+')

		self:process_status()
		if self.name == '' then
			return -1
		elseif self.name:sub(1, #multi_start) == multi_start then
			self.name = self.name:sub(#multi_start+1)
			self:recv_multi(inp)
		elseif self.name:sub(1, #binary_start) == binary_start then
			local ssize = self.args[1]
			self.name = self.args[2]
			self:recv_binary(ssize, inp)
		end

		if self.valid == false then
			self.name = ''
			return -1
		else
			return 0
		end
	end,

	execute = function(self)
		local command = self.commands[self.name]
		if command ~= nil then
			local rc = command.func(self)
			self.out:flush()
			return rc
		else
			return -1
		end
	end,

	-- inp requires readline() and read(size) methods
	--   readline() returns a string terminated with \n or \r\n
	--   		and strip those from the string.  wait until
	--   		\n or \r\n is found.
	--   read(size) returns a string (binary also) of size characters
	-- out requires write(string) and flush() methods
	--   write(string) writes string to output
	--   flush()    flushes the buffer (if output is buffered)
	process_transaction = function(self, inp, out)
		self.out = out
		local rc = self:recv_transaction(inp)
		if rc < 0 then
			return rc
		end
		return self:execute()
	end,
})

slop.Slop = Class(slop.Transaction, {
	new = function(self)
		slop.Transaction.new(self)

		self:add('help', slop.help, 'commands*')
		self:add('limits', slop.limits, '')
	end,
})

slop.TCPSlopServer = Class(slop.Slop, {
	new = function(self, port)
		slop.Slop.new(self)
		self.stream = stream.TCPStream(stream.NOFD, 32768, 5)

		self.tcp = self.stream.tcp
		self.tcp:nonblock()
		self.tcp:reuseaddr()
		self.tcp:bind('*', port)
		self.tcp:listen()
	end,

	process = function(self)
		local inout = self.stream
		local rc, from = self.tcp:accept(1) -- luacheck: ignore
		if rc > 0 then
			inout:reopen(rc)
			while rc >= 0 do
				rc = self:process_transaction(inout, inout)
			end
			inout:reopen(stream.NOFD)
		end

		return rc
	end,
})

local function main()
	local server = slop.TCPSlopServer(10000)

	local function echo(xact)
		local s = join(xact.args, ' ')
		if #xact.multi then
			local multi = {}
			for _,line in ipairs(xact.multi) do
				insert(multi, strip(line))
			end
			return xact:send_multi(s, multi)
		else
			return xact:send_binary(s, xact.binary)
		end
	end

	server.vars = { }

	local function set(xact)
		if #xact.args < 2 then
			return xact:send_single('name value')
		else
			local n = remove(xact.args, 1)
			local v = join(xact.args, ' ')
			xact.vars[n] = v
			return xact:send_single(format('%s %s', n, v))
		end
	end

	local function get(xact)
		local vars = {}

		if #xact.args > 0 then
			for _,n in ipairs(xact.args) do
				local v = xact.vars[n] or '<not found>'
				insert(vars, format('%s %s', n, v))
			end
		else
			for n,v in pairs(xact.vars) do
				insert(vars, format('%s %s', n, v))
			end
		end
		return xact:send_multi(join(xact.args, ' '), vars)
	end

	local function del(xact)
		local vars = {}
		if #xact.args > 0 then
			for _,n in ipairs(xact.args) do
				if xact.vars[n] then
					xact.vars[n] = nil
					insert(vars, n .. ' removed')
				else
					insert(vars, n .. ' <not found>')
				end
			end
		end
		return xact:send_multi(join(xact.args, ' '), vars)
	end

	server:add('echo', echo, '[args]*\\n[data]*')
	server:add('set', set, 'name value')
	server:add('get', get, 'name*')
	server:add('del', del, 'name+')

	while true do
		server:process()
	end
end

if is_main() then
	main()
else
	return slop
end

