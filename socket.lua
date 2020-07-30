--
-- u s e f u l / s o c k e t . l u a
--
local socket = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  errno		=  ffi.errno
local  fstring		=  ffi.string
local  gc		=  ffi.gc
local  new		=  ffi.new
local  sizeof		=  ffi.sizeof

local bit		= require('bit')
local  bor		=  bit.bor

local errno		= require('posix.errno')
local unistd		= require('posix.unistd') -- luacheck: ignore
local fcntl		= require('posix.fcntl')
local sys_types		= require('posix.sys.types') -- luacheck: ignore
local sys_time		= require('posix.sys.time') -- luacheck: ignore
local sys_socket	= require('posix.sys.socket')
local posix_string	= require('posix.string') -- luacheck: ignore
local arpa_inet		= require('posix.arpa.inet') -- luacheck: ignore
local netdb		= require('posix.netdb')
local netinet_in	= require('posix.netinet.in')
local netinet_tcp	= require('posix.netinet.tcp') -- luacheck: ignore
local poll		= require('posix.poll')

local class		= require('useful.class')
local  Class		=  class.Class
local stdio		= require('useful.stdio')
local  sprintf		=  stdio.sprintf
local  printf		=  stdio.printf
local system		= require('useful.system')
local  is_main		=  system.is_main

function socket.syserror(call)
	return sprintf("%s: %s\n", call, fstring(C.strerror(errno())))
end

function socket.getaddrinfo(host, port, protocol)
	local hint		= new('struct addrinfo [1]')
	local ai		= new('struct addrinfo *[1]')
	hint[0].ai_flags	= netdb.AI_CANONNAME
	if host == '*' then
		host = '0.0.0.0'
	end
	local ret = C.getaddrinfo(host, tostring(port), hint, ai)
	if ret ~= 0 then
		printf('getaddrinfo(%s %s) error: %d %s\n', host, port,
			ret, fstring(C.gai_strerror(ret)))
		os.exit(-1)
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
	addr[0].sin_family = sys_socket.AF_INET
	C.freeaddrinfo(ai[0])
	return addr
end

socket.Socket = Class({
	new = function(self, fd, port)
		self.fd		= fd or -1
		self.port	= port or -1
	end,

	setsockopt = function(self, level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		valuelen = valuelen or sizeof(value)
		local rc = C.setsockopt(self.fd, level, option, value, valuelen)
		if rc < 0 then
			return nil, socket.syserror('setsockopt')
		end
		return rc
	end,

	getsockopt = function(self, level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		valuelen = valuelen or sizeof(value)
		return C.getsockopt(self.fd, level, option, value, valuelen)
	end,

	nonblock = function(self)
		if self.fd < 0 then
			return -1
		end
		local ret = C.fcntl(self.fd, fcntl.F_GETFL)
		return C.fcntl(self.fd, bor(ret, fcntl.O_NONBLOCK))
	end,

	poll = function(self, events, timeout)
		local pfd	= new('struct pollfd[1]')
		pfd[0].fd	= self.fd
		pfd[0].events	= events
		local rc = C.poll(pfd, 1, timeout * 1000)
		if rc <= 0 then
			ffi.errno(errno.EAGAIN)
		end
		return rc
	end,

	reuseaddr = function(self)
		local value = new('int[1]', 1)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_REUSEADDR, value)
	end,

	rcvbuf = function(self, size)
		local value = new('int[1]', size)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVBUF, value)
	end,

	sndbuf = function(self, size)
		local value = new('int[1]', size)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_SNDBUF, value)
	end,

	rcvtimeo = function(self, timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = new('struct timeval[1]', {{sec, frac*1e6}})
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVTIMEO, tv, sizeof(tv[0]))
	end,

	sndtimeo = function(self, timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = new('struct timeval[1]', {{sec, frac*1e6}})
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_SNDTIMEO, tv, sizeof(tv[0]))
	end,

	bind = function(self, address, port)
		local addr = socket.getaddrinfo(address, port)
		local addrp = cast('struct sockaddr *', addr)
		local rc = C.bind(self.fd, addrp, sizeof(addr[0]))
		if rc < 0 then
			return nil, socket.syserror('bind')
		end
		return rc
	end,

	recv = function(self, buf, len, flags)
		return C.recv(self.fd, buf, len, flags or 0)
	end,

	send = function(self, buf, len, flags)
		return C.send(self.fd, buf, len, flags or 0)
	end,

	close = function(self)
		return C.close(self.fd)
	end,
})

socket.TCP = Class(socket.Socket, {
	new = function(self, fd)
		socket.Socket.new(self, fd, port)
		if fd == nil then
			self.fd = C.socket(sys_socket.AF_INET,
					sys_socket.SOCK_STREAM, 0)
		end
		if self.fd < 0 then
			return nil, socket.syserror("socket")
		end
		self.fdgc = cast('void *', self.fd)
		self.fdgc = gc(self.fdgc, function() C.close(self.fd) end)
	end,

	listen = function(self, backlog)
		local rc = C.listen(self.fd, backlog or 5)
		if rc < 0 then
			return nil, socket.syserror('listen')
		end
		return rc
	end,

	accept = function(self, timeout)
		local from	= new('struct sockaddr_in[1]')
		local fromp	= cast('struct sockaddr *', from)
		local size	= new('socklen_t[1]', sizeof(from))
		local rc	= self:poll(poll.POLLIN, timeout)
		if rc > 0 then
			rc = C.accept(self.fd, fromp, size)
		else
			rc = -1
		end
		return rc, from[0]
	end,

	connect = function(self, host, port)
		local addr	= socket.getaddrinfo(host, port)
		local addrp	= cast('struct sockaddr *', addr)
		local size	= sizeof(addr)
		local rc = C.connect(self.fd, addrp, size)
		if rc < 0 then
			return nil, socket.syserror('connect')
		end
		return rc
	end,
})

socket.UDP = Class(socket.Socket, {
	new = function(self)
		socket.Socket.new(self)
		self.fd = C.socket(sys_socket.AF_INET, sys_socket.SOCK_DGRAM, 0)
		if self.fd < 0 then
			return nil, socket.syserror("socket")
		end
		self.fdgc = cast('void *', self.fd)
		self.fdgc = gc(self.fdgc, function() C.close(self.fd) end)
	end,

	recvfrom = function(self, buf, len)
		local from	= new('struct sockaddr_in[1]')
		local fromp	= cast('struct sockaddr *', from)
		local size	= new('uint32_t[1]', sizeof(from))
		local ret = C.recvfrom(self.fd, buf, len, 0, fromp, size)
		return ret, from[0]
	end,

	sendto = function(self, buf, len, addr)
		local addrp	= cast('struct sockaddr *', addr)
		return C.sendto(self.fd, buf, len, 0, addrp, sizeof(addr))
	end,

	add_membership = function(self, addr, port)
		addr		= socket.getaddrinfo(addr, port)
		local imreq	= new('struct ip_mreq[1]')
		imreq.imr_multiaddr = addr
		return self:setsockopt(netinet_in.IPPROTO_IP,
				netinet_in.IP_ADD_MEMBERSHIP,
				imreq, sizeof(imreq))
	end,

	drop_membership = function(self, addr, port)
		addr		= socket.getaddrinfo(addr, port)
		local imreq	= new('struct ip_mreq[1]')
		imreq.imr_multiaddr = addr
		return self:setsockopt(netinet_in.IPPROTO_IP,
				netinet_in.IP_DROP_MEMBERSHIP,
				imreq, sizeof(imreq))
	end,
})

local function main()
end

if is_main() then
	main()
else
	return socket
end

