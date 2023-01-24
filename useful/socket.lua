--
-- u s e f u l / s o c k e t . l u a
--
local socket = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  errno		=  ffi.errno
local  fstring		=  ffi.string
local  new		=  ffi.new
local  sizeof		=  ffi.sizeof

local bit		= require('bit')
local  bor		=  bit.bor

			  require('posix.errno')
local unistd		= require('posix.unistd') -- luacheck: ignore
			  require('posix.fcntl')
local sys_types		= require('posix.sys.types') -- luacheck: ignore
local sys_time		= require('posix.sys.time') -- luacheck: ignore
			  require('posix.sys.socket')
local posix_string	= require('posix.string') -- luacheck: ignore
local arpa_inet		= require('posix.arpa.inet') -- luacheck: ignore
			  require('posix.netdb')
local netinet_in	= require('posix.netinet.in')
local netinet_tcp	= require('posix.netinet.tcp') -- luacheck: ignore
			  require('posix.poll')

local class		= require('useful.class')
local  Class		=  class.Class
local stdio		= require('useful.stdio')
local  sprintf		=  stdio.sprintf

local errno_string = function(call)
	local err = errno()
	return sprintf("%s: %d %s\n", call, err, fstring(C.strerror(err)))
end

socket.errno_string = errno_string

local function getaddrinfo(host, port, protocol)
	local hint		= new('struct addrinfo [1]')
	local ai		= new('struct addrinfo *[1]')
	if host == '*' then
		host = '0.0.0.0'
	end
	local ret = C.getaddrinfo(host, tostring(port), hint, ai)
	if ret ~= 0 then
		local s
		if ret == C.EAI_SYSTEM then
			s = errno_string('getaddrinfo')
		else
			s = sprintf('getaddrinfo(%s, %s): %d %s\n',
				host, port, ret, fstring(C.gai_strerror(ret)))
		end
		return nil, s
	end

	local a = ai[0]
	if protocol ~= nil then
		while a ~= nil and a.ai_protocol ~= protocol do
			a = a.ai_next
		end
	end
	local addr = new('struct sockaddr_in [1]')
	if a ~= nil then
		local sinp = cast('struct sockaddr_in *', a.ai_addr)
		addr[0].sin_addr.s_addr	= sinp.sin_addr.s_addr
		addr[0].sin_port	= sinp.sin_port
	else
		addr[0].sin_addr.s_addr	= netinet_in.INADDR_ANY
		addr[0].sin_port	= C.htons(port)
	end
	addr[0].sin_family = C.AF_INET
	C.freeaddrinfo(ai[0])
	return addr
end
socket.getaddrinfo = getaddrinfo

socket.addr_to_ip_port = function(addrp)
	local host = fstring(C.inet_ntoa(addrp[0].sin_addr))
	local port = C.htons(addrp[0].sin_port)
	return host, port
end

socket.Socket = Class({
	new = function(self, fd, port)
		self.fd		= fd or -1
		self.port	= port or -1
	end,

	__gc = function(self)
		if self.fd > -1 then
			self:close()
		end
	end,

	setsockopt = function(self, level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		valuelen = valuelen or sizeof(value)
		local rc = C.setsockopt(self.fd, level, option, value, valuelen)
		if rc < 0 then
			return nil, errno_string('setsockopt')
		end
		return rc
	end,

	getsockopt = function(self, level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		valuelen = new('uint32_t[1]', valuelen or sizeof(value))
		return C.getsockopt(self.fd, level, option, value, valuelen)
	end,

	nonblock = function(self)
		if self.fd < 0 then
			return -1
		end
		local ret = C.fcntl(self.fd, C.F_GETFL)
		return C.fcntl(self.fd, C.F_SETFL, bor(ret, C.O_NONBLOCK))
	end,

	poll = function(self, events, timeout)
		local pfd	= new('struct pollfd[1]')
		pfd[0].fd	= self.fd
		pfd[0].events	= events
		local rc = C.poll(pfd, 1, timeout * 1000)
		if rc <= 0 then
			errno(C.EAGAIN)
		end
		return rc
	end,

	reuseaddr = function(self)
		local value = new('int[1]', 1)
		return self:setsockopt(C.SOL_SOCKET, C.SO_REUSEADDR, value)
	end,

	reuseport = function(self)
		local value = new('int[1]', 1)
		return self:setsockopt(C.SOL_SOCKET, C.SO_REUSEPORT, value)
	end,

	rcvbuf = function(self, size)
		local value = new('int[1]', size or 0)
		if size ~= nil then
			return self:setsockopt(C.SOL_SOCKET, C.SO_RCVBUF, value)
		else
			self:getsockopt(C.SOL_SOCKET, C.SO_RCVBUF, value)
			return value[0]
		end
	end,

	sndbuf = function(self, size)
		local value = new('int[1]', size or 0)
		if size ~= nil then
			return self:setsockopt(C.SOL_SOCKET, C.SO_SNDBUF, value)
		else
			self:getsockopt(C.SOL_SOCKET, C.SO_SNDBUF, value)
			return value[0]
		end
	end,

	rcvtimeo = function(self, timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = new('struct timeval[1]', {{sec, frac*1e6}})
		return self:setsockopt(C.SOL_SOCKET,
				C.SO_RCVTIMEO, tv, sizeof(tv[0]))
	end,

	sndtimeo = function(self, timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = new('struct timeval[1]', {{sec, frac*1e6}})
		return self:setsockopt(C.SOL_SOCKET,
				C.SO_SNDTIMEO, tv, sizeof(tv[0]))
	end,

	bind = function(self, address, port)
		local addr,err	= getaddrinfo(address, port)
		if addr == nil then
			return nil, err
		end
		local addrp	= cast('struct sockaddr *', addr)
		local rc	= C.bind(self.fd, addrp, sizeof(addr[0]))
		if rc < 0 then
			return nil, errno_string('bind')
		end
		return rc, addr
	end,

	connect = function(self, host, port)
		local addr,err	= getaddrinfo(host, port)
		if addr == nil then
			return nil, err
		end
		local addrp	= cast('struct sockaddr *', addr)
		local size	= sizeof(addr)
		local rc	= C.connect(self.fd, addrp, size)
		if rc < 0 then
			return nil, errno_string('connect')
		end
		return rc
	end,

	recv = function(self, buf, len, flags)
		local rc = C.recv(self.fd, buf, len, flags or 0)
		if rc < 0 then
			return nil, errno_string('recv')
		end
		return rc
	end,

	send = function(self, buf, len, flags)
		local rc = C.send(self.fd, buf, len, flags or 0)
		if rc < 0 then
			return nil, errno_string('send')
		end
		return rc
	end,

	recv_all = function(self, buf, len)
		local p		= cast('char *', buf)
		while len > 0 do
			local n, err = self:recv(p, len)
			if n then
				p	= p + n
				len	= len - n
			elseif p - buf > 0 then
				return p - buf
			else
				return n, err
			end
		end
		return p - buf
	end,

	send_all = function(self, buf, len)
		local p		= cast('char *', buf)
		while len > 0 do
			local n, err = self:send(buf, len)
			if n then
				p	= p + n
				len	= len - n
			elseif p - buf > 0 then
				return p - buf
			else
				return n, err
			end
		end
		return p - buf
	end,

	close = function(self)
		local rc = C.close(self.fd)
		self.fd = -1
		return rc
	end,
})

socket.TCP = Class(socket.Socket, {
	new = function(self, fd, port)
		socket.Socket.new(self, fd, port)
		if fd == nil then
			self.fd = C.socket(C.AF_INET, C.SOCK_STREAM, 0)
		end
		if self.fd < 0 then
			return nil, errno_string("socket")
		end
	end,

	nodelay = function(self, nodelay)
		local value = new('int[1]', nodelay)
		return self:setsockopt(C.IPPROTO_TCP, C.TCP_NODELAY, value)
	end,

	listen = function(self, backlog)
		local rc = C.listen(self.fd, backlog or 5)
		if rc < 0 then
			return nil, errno_string('listen')
		end
		return rc
	end,

	accept = function(self, timeout)
		local from	= new('struct sockaddr_in[1]')
		local fromp	= cast('struct sockaddr *', from)
		local size	= new('socklen_t[1]', sizeof(from))
		local rc	= self:poll(C.POLLIN, timeout)
		if rc > 0 then
			rc = C.accept(self.fd, fromp, size)
		else
			rc = -1
		end
		return rc, from[0]
	end,

	shutdown = function(self)
		local rc = C.shutdown(self.fd, C.SHUT_WR)
		if rc <= 0 then
			local err = errno()
			self:close()
			errno(err)
			return nil, errno_string('shutdown')
		end
		rc = C.recv(self.fd, new('char[?]', 1))
		self:close()
		if rc < 0 then
			return nil, errno_string('recv')
		end
		return 0
	end,
})

socket.UDP = Class(socket.Socket, {
	new = function(self)
		socket.Socket.new(self)
		self.fd = C.socket(C.AF_INET, C.SOCK_DGRAM, 0)
		if self.fd < 0 then
			return nil, errno_string('socket')
		end
	end,

	recvfrom = function(self, buf, len)
		local from	= new('struct sockaddr_in[1]')
		local fromp	= cast('struct sockaddr *', from)
		local size	= new('uint32_t[1]', sizeof(from))
		local ret	= C.recvfrom(self.fd, buf, len, 0, fromp, size)
		return ret, from[0]
	end,

	sendto = function(self, buf, len, addr)
		local addrp	= cast('struct sockaddr *', addr)
		return C.sendto(self.fd, buf, len, 0, addrp, sizeof(addr))
	end,

	sendmmsg = function(self, msgs, nmsgs, flags)
		return C.sendmmsg(self.fd, msgs, nmsgs, flags or 0)
	end,

	recvmmsg = function(self, msgs, nmsgs, flags, timeout)
		return C.recvmmsg(self.fd, msgs, nmsgs, flags or 0, timeout or nil)
	end,

	ip_multicast_if = function(self, addr)
		addr		= getaddrinfo(addr, 0)
		local imreq	= new('struct ip_mreqn[1]')
		imreq[0].imr_address.s_addr = addr[0].sin_addr.s_addr
		return self:setsockopt(C.IPPROTO_IP, C.IP_MULTICAST_IF,
				imreq, sizeof(imreq))
	end,

	add_membership = function(self, addr, ifaddr)
		addr		= getaddrinfo(addr, 0)
		local imreq	= new('struct ip_mreqn[1]')
		imreq[0].imr_multiaddr.s_addr = addr[0].sin_addr.s_addr
		if ifaddr ~= nil then
			ifaddr	= getaddrinfo(ifaddr, 0)
			imreq[0].imr_address.s_addr = ifaddr[0].sin_addr.s_addr
		end
		return self:setsockopt(C.IPPROTO_IP, C.IP_ADD_MEMBERSHIP,
				imreq, sizeof(imreq))
	end,

	drop_membership = function(self, addr)
		addr		= getaddrinfo(addr, 0)
		local imreq	= new('struct ip_mreqn[1]')
		imreq[0].imr_multiaddr.s_addr = addr[0].sin_addr.s_addr
		return self:setsockopt(C.IPPROTO_IP, C.IP_DROP_MEMBERSHIP,
				imreq, sizeof(imreq))
	end,
})

return socket
