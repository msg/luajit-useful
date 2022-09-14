#!/usr/bin/luajit

local scheduler_socket = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  cast	=  ffi.cast
local  errno	=  ffi.errno

local bit	= require('bit')
local  band	=  bit.band
local  bor	=  bit.bor

		  require('posix.poll')

local class		= require('useful.class')
local  Class		=  class.Class
local scheduler		= require('useful.scheduler')
local  check		=  scheduler.check
local socket		= require('useful.socket')
local time		= require('useful.time')
local  now		=  time.now

local wait_for_events = function(pfd, timeout)
	local start = now()
	local dt
	check(function()
		dt = time.dt(now(), start)
		if timeout and dt > timeout then
			return true
		end
		return band(pfd.revents, bor(pfd.events, C.POLLERR)) ~= 0
	end)
	if band(pfd.revents, bor(C.POLLHUP, C.POLLERR)) ~= 0 then
		return -1
	elseif timeout and dt > timeout then
		errno(C.ETIMEDOUT)
		return -1
	else
		return 0
	end
end
socket.wait_for_events = wait_for_events

local  socket_TCP	=  socket.TCP
local TCP = Class(socket_TCP, {
	new = function(self, fd, port)
		socket_TCP.new(self, fd, port)
		self:nonblock()
		self.timeout		= 0.001
		self.on_error_func	= self.default_error_func
	end,

	set_timeout = function(self, timeout)
		self.timeout	= timtout
	end,

	on_error = function(self, func)
		local prev_error_func	= self.on_error_func
		self.on_error_func	= func
		return prev_error_func
	end,

	default_error_func = function(self)		--luacheck:ignore
		error('error: '..tostring(errno())..'\n'..debug.traceback())
	end,

	accept = function(self)
		self.pfd.events	= C.POLLIN
		while true do
			if wait_for_events(self.pfd, self.timeout) < 0 then
				self:on_error_func()
			end
			local fd = socket_TCP.accept(self, 0)
			if fd < 0 then
				self:on_error_func()
			else
				return fd
			end
		end
	end,

	recv = function(self, buf, len, flags)
		self.pfd.events	= C.POLLIN
		while true do
			if wait_for_events(self.pfd, self.timeout) < 0 then
				self:on_error_func()
			end
			local n = socket_TCP.recv(self, buf, len, flags)
			if n == 0 then
				errno(C.EBADF)
				self:on_error_func()
			elseif n < 0 then
				self:on_error_func()
			else
				return n
			end
		end
	end,


	recv_all = function(self, buf, len)
		local p		= cast('char *', buf)
		while len > 0 do
			local rc = self:recv(p, len, C.MSG_DONTWAIT)
			if rc > 0 then
				p	= p + rc
				len	= len - rc
			else
				return rc
			end
		end
		return p - buf
	end,

	send = function(self, buf, len, flags)
		self.pfd.events	= C.POLLOUT
		while true do
			if wait_for_events(self.pfd, self.timeout) < 0 then
				self:on_error_func()
			end
			local n = socket_TCP.send(self, buf, len, flags)
			if n < 0 then
				self:on_error_func()
			else
				return n
			end
		end
	end,

	send_all = function(self, buf, len)
		local nbytes = 0
		while len > 0 do
			local n = self:send(buf, len, C.MSG_NOSIGNAL)
			nbytes = nbytes + n
			buf = buf + n
			len = len - n
		end
		return nbytes
	end,

})
scheduler_socket.TCP = TCP

return scheduler_socket
