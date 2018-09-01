--
-- u s e f u l / s l o p . l u a
--
local function is_main()
	return debug.getinfo(4) == nil
end

if not is_main() then
	module(..., package.seeall)
end

local ffi	= require('ffi')

local strings	= require('useful.strings')
local tables	= require('useful.tables')
local log	= require('useful.log')
local socket	= require('useful.socket')
local stream	= require('useful.stream')

local strip = strings.strip
local rstrip = strings.rstrip
local lstrip = strings.lstrip
local split = strings.split
local ljust = strings.ljust

local format = string.format

local insert = table.insert
local remove = table.remove
local join = table.concat

local line_limit = 256
local multi_limit = 256
local binary_limit = 1024 * 1024

local eol = '\n'
local one_start = ''
local multi_start = '<'
local multi_end = '>'
local binary_start = '['
local binary_end = ']'
local error_start = '?'

local printf = function(...) io.stdout:write(string.format(...)) end

-- global commands
function help(xact)
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
		cmd = commands[name]
		if cmd == nil then
			usage = 'invalid command' + eol
		else
			usage = cmd.name .. ' ' .. cmd.usage
		end
		local s = ljust(name .. ': ', ml) ..  strip(usage)
		insert(multi, s)
	end
	return xact.send_multi(join(xact.args, ' '), multi)
end

function limits(xact)
	local s = string.format('%d %d %d', xact.line_limit,
			xact.multi_limit, xact.binary_limit)
	return xact.send_single(s)
end

function Transaction()
	local self = {
		done		= false,
		commands	= {},
		line_limit	= line_limit,
		multi_limit	= multi_limit,
		binary_limit	= binary_limit,
	}

	function self.reset()
		self.seq = nil
		self.binary = nil
		self.multi = {}
		self.error = false
		self.valid = true
		self.name = ''
		self.error_message = ''
	end

	function self.add(name, func, usage)
		self.commands[name] = { name=name, func=func, usage=usage }
	end

	function self.write(data)
		self.out.write(ffi.cast('char *', data), #data)
	end

	function self.send(leader, message)
		local s = {}
		if self.error then insert(s, error_start) end
		if self.seq ~= nil then insert(s, self.seq) end
		if self.name then insert(s, self.name) end
		insert(s, message .. eol)
		self.write(leader .. join(s, ' '))
	end

	function self.finish(leader)
		if leader ~= '' then
			self.write(leader .. eol)
		end
		self.out.flush()
	end

	function self.send_single(message)
		self.send('', message)
		self.finish('')
		return 0
	end

	function self.send_multi(message, multi)
		self.send(multi_start, message)
		if #multi > 0 then
			self.write(join(multi, eol))
			self.write(eol)
		end
		self.finish(multi_end)
		return 0
	end

	function self.send_binary(message, binary)
		self.send(binary_start, #binary .. message)
		self.write(binary)
		self.finish(binary_end)
		return 0
	end

	function self.send_transaction(inp, out, requestion, data)
		self.reset()
		self.out = out
		if type(data) == 'table' then
			self.send_multi(request, data)
		elseif type(data) == 'string' then
			self.send_binary(request, data)
		else
			self.send_single(request)
		end
		return self.recv_transaction(inp)
	end

	function self.readline(inp)
		local rc
		local buf = ffi.new('char[?]', line_limit)
		rc = inp.readline(buf, line_limit)
		if rc <= 0 then
			return ''
		end
		if string.char(buf[rc-1]) ~= '\n' then
			return ''
		end
		return ffi.string(buf, rc)
	end

	function self.process_status()
		if #self.args < 1 then
			return
		end

		if self.args[1] == error_start then
			self.error = true
			remove(self.args, 1)
		end

		local arg = remove(self.args, 1)
		local c = arg:sub(1,1):byte()
		if not (48 <= c and c <= 57) then -- '0' <= c <= '9'
			self.name = arg
		else
			self.seq = tonumber(arg)
			self.name = remove(self.args, 1)
		end
	end

	function self.recv_multi(inp)
		self.multi = {}
		local line
		for i=1,#multi_limit do
			line = self.readline(inp)
			if line:sub(#line-#eol) ~= eol then
				break
			end
			if line:sub(1,#multi_end) == multi_end then
				break
			end
			insert(self.multi, strip(line))
		end
		if line:sub(1,#multiend) ~= multi_end then
			self.error_message = 'max line limit ' .. multi_limit
			self.valid = false
		end
	end

	function self.recv_binary(ssize, inp)
		self.valid = false
		local size = tonumber(ssize)
		if size == nil then
			self.error_message = 'bad size "' .. ssize .. '" format'
			return
		end
		if size > binary_limit then
			self.error_message = 'max binary size ' .. binary_limit
			return
		end

		self.binary = inp.read(size)

		line = self.readline(inp)
		if not line:sub(1, #binary_end) ~= binary_end then
			self.error_message = 'no binary end'
		else
			self.valid = true
		end
	end

	function self.recv_transaction(inp)
		self.reset()
		self.status = self.readline(inp)
		if self.status == '' or
		   self.status:sub(#self.status-(#eol-1)) ~= eol then
			return -1
		end
		self.args = split(strip(self.status), '%s+')

		self.process_status()
		if self.name == nil then
			return -1
		elseif self.name.sub(1, #multi_start) == multi_start then
			self.name = self.name:sub(#multi_start+1)
			self.recv_multi(inp)
		elseif self.name.sub(1, #binary_start) == binary_start then
			ssize = self.args[1]
			self.name = slef.args[2]
			self.recv_binary(ssize, inp)
		end

		if self.valid == false then
			self.name = ''
			return -1
		else
			return 0
		end
	end

	function self.execute()
		command = self.commands[self.name]
		if command ~= nil then
			rc = command.func(self)
			self.out.flush()
			return rc
		else
			return -1
		end
	end

	-- inp requires readline() and read(size) methods
	--   readline() returns a string terminated with \n or \r\n
	--   		and strip those from the string.  wait until
	--   		\n or \r\n is found.
	--   read(size) returns a string (binary also) of size characters
	-- out requires write(string) and flush() methods
	--   write(string) writes string to output
	--   flush()    flushes the buffer (if output is buffered)
	function self.process_transaction(inp, out)
		self.out = out
		local rc = self.recv_transaction(inp)
		if rc < 0 then
			return rc
		end
		return self.execute()
	end

	self.reset()
	return self
end

function Slop()
	local self = Transaction()

	self.add('help', help, 'commands*')
	self.add('limits', limits, '')

	return self
end

function TCPSlopServer(port)
	local self	= Slop()
	self.stream	= stream.TCPStream(stream.NOFD, 32768, 5)

	self.tcp	= socket.tcp()
	self.tcp.bind('*', port)
	self.tcp.listen()

	function self.process()
		local io = self.stream
		local rc, from = self.tcp.accept(4)
		if rc > 0 then
			io.reopen(rc)
			while rc >= 0 do
				rc = self.process_transaction(io, io)
			end
			io.reopen(stream.NOFD)
		else
			printf("%s\n", socket.syserror('accept'))
		end

		return rc
	end

	return self
end

function main()
	local server = TCPSlopServer(10000)

	function echo(xact)
		local s = join(xact.args, ' ')
		if #xact.multi then
			local multi = {}
			for _,line in ipairs(xact.multi) do
				insert(multi, strip(line))
			end
			return xact.send_multi(s, multi)
		else
			return xact.send_binary(s, xact.binary)
		end
	end

	server.vars = { }

	function set(xact)
		if #xact.args < 2 then
			return xact.send_single('name value')
		else
			local n = remove(xact.args, 1)
			local v = join(xact.args, ' ')
			xact.vars[n] = v
			return xact.send_single(format('%s %s', n, v))
		end
	end

	function get(xact)
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
		return xact.send_multi(join(xact.args, ' '), vars)
	end

	function del(xact)
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
		return xact.send_multi(join(xact.args, ' '), vars)
	end

	server.add('echo', echo, '[args]*\\n[data]*')
	server.add('set', set, 'name value')
	server.add('get', get, 'name*')
	server.add('del', del, 'name+')
	return server.process()
end

if is_main() then
	main()
end

