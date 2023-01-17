#!/usr/bin/luajit

local socket = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  errno		=  ffi.errno
local  fstring		=  ffi.string
local  new		=  ffi.new
local  sizeof		=  ffi.sizeof

local bit		= require('bit')
local  band		=  bit.band
local  bor		=  bit.bor

			  require('posix.errno')
			  require('posix.string')

local class		= require('useful.class')
local  Class		=  class.Class
local poll		= require('useful.scheduler.poll')
local  check		=  poll.check
local  run		=  poll.run
local  scheduler	=  poll.scheduler
local  spawn		=  poll.spawn
local socket_		= require('useful.socket')
local  socket_Socket	=  socket_.Socket
local  socket_TCP	=  socket_.TCP
local  socket_UDP	=  socket_.UDP
local  close		=  socket_TCP.close
local time		= require('useful.time')
local  now		=  time.now

local errno_message = function()
	local e = errno()
	if e == C.EAGAIN or e == C.EWOULDBLOCK or e == C.ETIMEDOUT then
		return 'timeout'
	elseif e == C.EBADF then
		return 'closed'
	else
		return tostring(e)..' '..fstring(C.strerror(e))
	end
end
socket.errno_message = errno_message

local wait_for_event = function(sock, timeout)
	local start = now()
	local ok, err, dt
	check(function()
		local pfd = sock.pfd
		local revents = pfd.revents
		pfd.revents = 0
		dt = time.dt(now(), start)
		if timeout and timeout < dt then
			errno(C.EAGAIN)
			ok, err = nil, errno_message()
			return true
		elseif band(revents, bor(C.POLLHUP, C.POLLERR, C.POLLNVAL)) ~= 0 then
			ok = pfd.revents
			return true
		elseif band(revents, pfd.events) ~= 0 then
			ok = pfd.revents
			return true
		else
			ok = -1
			return false
		end
	end)
	return ok, err
end

local Socket = Class(socket_Socket, {
	new = function(self, fd, port, timeout, poll_)
		socket_Socket.new(self, fd, port)
		self:nonblock()
		self.timeout	= timeout or 0.05
		self.poll	= poll_ or scheduler.poll
		if self.poll ~= nil then
			self.poll:add(self)
		end
	end,

	close = function(self)
		assert(self.fd > -1)
		if self.poll ~= nil then
			self.poll:remove(self)
		end
		return close(self)
	end,

	wait_for_events = function(self, timeout, events)
		self.pfd.events = events
		local ok, err = wait_for_event(self, timeout)
		return ok, err
	end,

	recv = function(self, buf, len, flags)
		local ok, err = self:wait_for_events(self.timeout, C.POLLIN)
		if not ok then
			return ok,err
		end
		local n = C.recv(self.fd, buf, len, flags or 0)
		if n == 0 then
			errno(C.EBADF)
			return nil, errno_message()
		elseif n < 0 then
			return nil, errno_message()
		else
			return tonumber(n)
		end
	end,


	recv_all = function(self, buf, len)
		local p		= cast('char *', buf)
		while len > 0 do
			local n, msg = self:recv(p, len)
			if not n then
				return n, msg, p - buf
			end
			p	= p + n
			len	= len - n
		end
		return p - buf
	end,

	send = function(self, buf, len, flags)
		local ok, err = self:wait_for_events(self.timeout, C.POLLOUT)
		if not ok then
			return ok,err
		end
		local n = C.send(self.fd, buf, len, flags or 0)
		if n < 0 then
			return nil, errno_message()
		else
			return tonumber(n)
		end
	end,

	send_all = function(self, buf, len)
		local nbytes = 0
		while len > 0 do
			local n, msg = self:send(buf, len)
			if not n then
				return n, msg, nbytes
			end
			nbytes = nbytes + n
			buf = buf + n
			len = len - n
		end
		return nbytes
	end,
})
socket.Socket = Socket

local TCP = Class(socket_TCP, Socket, {
	new = function(self, fd, port, timeout, poll_)
		socket_TCP.new(self, fd, port)
		Socket.new(self, self.fd, self.port, timeout, poll_)
		self:nodelay(1)
	end,

	shutdown = function(self)
		local rc = C.shutdown(self.fd, C.SHUT_WR)
		if rc < 0 then
			return nil, errno_message()
		end
		local ok, err = self:recv(new('char[?]', 1), 1)
		self:close()
		return ok, err
	end,

	accept = function(self)
		local ok, err = self:wait_for_events(self.timeout, C.POLLIN)
		if not ok then
			return ok, err
		end
		local from	= new('struct sockaddr_in[1]')
		local fromp	= cast('struct sockaddr *', from)
		local size	= new('socklen_t[1]', sizeof(from))
		local fd = C.accept(self.fd, fromp, size)
		if fd < 0 then
			return nil, errno_message()
		else
			return fd, from
		end
	end,
})
socket.TCP = TCP

local UDP = Class(socket_UDP, Socket, {
	new = function(self, fd, port, timeout, poll_)
		socket_UDP.new(self, fd, port)
		Socket.new(self, self.fd, self.port, timeout, poll_)
	end,


	sendto = function(self, buf, len, addr)
		local ok, err = self:wait_for_events(self.timeout, C.POLLOUT)
		if not ok then
			return ok,err
		end
		local addrp = cast('struct sockaddr *', addr)
		local n = C.sendto(self.fd, buf, len, 0, addrp, sizeof(addr))
		if n < 0 then
			return nil, errno_message()
		else
			return tonumber(n)
		end
	end,

	recvfrom = function(self, buf, len)
		local ok, err = self:wait_for_events(self.timeout, C.POLLIN)
		if not ok then
			return ok,err
		end
		local from      = new('struct sockaddr_in[1]')
		local fromp     = cast('struct sockaddr *', from)
		local size      = new('uint32_t[1]', sizeof(from))
		local n = C.recvfrom(self.fd, buf, len, 0, fromp, size)
		if n == 0 then
			errno(C.EBADF)
			return nil, errno_message()
		elseif n < 0 then
			return nil, errno_message()
		else
			return tonumber(n), from[0]
		end
	end,

	sendmmsg = function(self, msgs, nmsgs, flags)
		local ok, err = self:wait_for_events(self.timeout, C.POLLOUT)
		if not ok then
			return ok,err
		end
		local n = C.sendmmsg(self.fd, msgs, nmsgs, flags or 0)
		if n == 0 then
			return nil, errno_message()
		elseif n < 0 then
			return nil, errno_message()
		else
			return tonumber(n)
		end
	end,

	recvmmsg = function(self, msgs, nmsgs, flags, timeout)
		local ok, err = self:wait_for_events(self.timeout, C.POLLIN)
		if not ok then
			return ok,err
		end
		local n = C.recvmmsg(self.fd, msgs, nmsgs, flags or 0, timeout or nil)
		if n == 0 then
			return nil, errno_message()
		elseif n < 0 then
			return nil, errno_message()
		else
			return tonumber(n)
		end
	end,
})
socket.UDP = UDP

socket.TCPServer = Class({
	new = function(self, port, client_func, options)
		options = options or { }
		-- max must be >= 2 (1 for bound socket, +n for n clients)
		options.max	= options.max or 2
		self.options	= options
		scheduler:resize(options.max)
		local sock	= TCP()
		sock:reuseaddr()
		sock:bind(options.host or '*', port)
		sock:listen(options.listen or 5)
		sock.timeout	= options.timeout or 0.1
		self.sock	= sock
		spawn(self.server, self, client_func)
	end,

	accept = function(self, client_func, fd, id, addr)	--luacheck:ignore
		local sock = TCP(fd)
		spawn(client_func, sock, id, addr)
	end,

	idle = function(self)				--luacheck:ignore
	end,

	server = function(self, client_func)
		local max = self.options.max
		local limit = function()
			return #scheduler < max
		end
		local id = 1
		while true do
			check(limit)
			local fd, addr_or_err = self.sock:accept(0)
			if fd then
				self:accept(client_func, fd, id, addr_or_err)
				id = id + 1
			elseif addr_or_err ~= 'timeout' then
				error(addr_or_err)
				break
			else
				self:idle()
			end
		end
	end,

	run = function(self)				--luacheck:ignore
		run()
	end,
})

return socket
