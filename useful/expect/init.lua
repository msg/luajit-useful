#!/usr/bin/luajit
--
-- e x p e c t / i n i t . l u a
--
local init = { }

local  find	=  string.find

local ffi	= require('ffi')
local  C	=  ffi.C

		  require('posix.errno')
		  require('posix.poll')
		  require('posix.unistd')

local class	= require('useful.class')
local  Class	=  class.Class
local time	= require('useful.time')

local pty	= require('useful.expect.pty')

local function setblocking(fd, blocking)
	local fl = C.fcntl(fd, C.F_GETFL)
	if blocking == true then
		fl = bit.band(fl, bit.bnot(C.O_NONBLOCK))
	else
		fl = bit.bor(fl, C.O_NONBLOCK)
	end
	if C.fcntl(fd, C.F_SETFL, fl) < 0 then
		return nil, 'fcntl F_SETFL failed'
	else
		return true
	end
end

local function poll(fd, events, timeout)
	local pfd	= ffi.new('struct pollfd[1]')
	pfd[0].fd	= fd
	pfd[0].events	= events
	local rc = C.poll(pfd, 1, timeout * 1000)
	if rc <= 0 then
		return rc
	end
	return rc
end

local function read(fd, size, timeout)
	if poll(fd, C.POLLIN, timeout) > 0 then
		local buf = ffi.new('char[?]', size)
		local rc = C.read(fd, buf, size)
		if rc < 0 then
			return nil, 'read failed'
		end
		return ffi.string(buf, rc)
	else
		return nil, 'timeout'
	end
end

local function write(fd, data, timeout)
	if poll(fd, C.POLLOUT, timeout) > 0 then
		local rc = C.write(fd, data, #data)
		if rc < 0 then
			return nil, 'write failed'
		end
		return rc
	else
		return nil, 'read timeout'
	end
end

init.Expect = Class({
	new = function(self, file, args, options)
		options		= options or {}
		self.cwd	= options.cwd or '.'
		self.cols	= options.cols or 80
		self.rows	= options.rows or 25
		self.timeout	= options.timeout or 30
		self.blocking	= options.blocking or true
		self.log_file	= options.log_file
		self.env	= {
			'PATH=/bin:/usr/bin:/usr/sbin:/usr/local/bin',
		}
		for _,env in ipairs(options.env or {}) do
			table.insert(self.env, env)
		end

		local pty_, err = pty.open(self.cols, self.rows)
		if not pty_ then
			return nil, err
		end

		local ok
		ok, err = setblocking(pty_.master, self.blocking)
		if not ok then
			return nil, err
		end
		ok, err = setblocking(pty_.slave, self.blocking)
		if not ok then
			return nil, err
		end

		self.fresh	= true
		self.buffer	= ''
		self.master	= pty_.master
		self.slave	= pty_.slave
		self.name	= pty_.name

		ok, err	= pty.spawn(self.master, self.slave, file, args,
			self.env, self.cwd, self.cols, self.rows)
		if not ok then
			return nil, err
		end
	end,

	expect = function(self, pattern, timeout, plain)
		if not self.fresh then
			return find(self.buffer, pattern, 1, plain), self.buffer
		end

		self.buffer = ''
		local try = (timeout or self.timeout) / 0.1
		while try > 0 do
			local data, err = self:read(4096, 0.1)
			if data then
				if self.log_file then
					self.log_file:write('< '..data)
				end
				self.buffer = self.buffer..data
				local s, _ = find(self.buffer, pattern, 1, plain)
				if s then
					return s, self.buffer
				end
			elseif err == 'timeout' then
				try = try - 1
			else
				return nil, err
			end
		end

		self.fresh = false

		return find(self.buffer, pattern, 1, plain), self.buffer
	end,

	sendline = function(self, line)
		if self.log_file then
			self.log_file:write('> '..line)
		end
		return self:write(line..'\r')
	end,

	read = function(self, size, timeout)
		return read(self.master, size, timeout or self.timeout)
	end,

	write = function(self, data, timeout)
		self.fresh = true
		return write(self.master, data, timeout or self.timeout)
	end,

	clean = function(self)
		C.close(self.master)
	end,

	getfd = function(self)
		return self.master
	end,

	wait = function(_, timeout)
		time.sleep(timeout)
	end,
})

return init
