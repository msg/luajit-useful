--
-- u s e f u l / s o c k e t . l u a
--
local socket = { }

local is_main	= require('useful.system').is_main

local ffi		= require('ffi')
local C			= ffi.C

local bit		= require('bit')
local bor		= bit.bor

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

local class		= require('useful.class')
local Class		= class.Class
local stdio		= require('useful.stdio')
local sprintf		= stdio.sprintf
local printf		= stdio.printf

function socket.syserror(call)
	return sprintf("%s: %s\n", call, ffi.string(C.strerror(ffi.errno())))
end

function socket.getaddrinfo(host, port, protocol)
	local hint		= ffi.new('struct addrinfo [1]')
	local ai		= ffi.new('struct addrinfo *[1]')
	hint[0].ai_flags	= netdb.AI_CANONNAME
	if host == '*' then
		host = '0.0.0.0'
	end
	local ret = C.getaddrinfo(host, tostring(port), hint, ai)
	if ret ~= 0 then
		printf('getaddrinfo(%s %s) error: %d %s\n', host, port,
			ret, ffi.string(C.gai_strerror(ret)))
		os.exit(-1)
	end

	local a = ai[0]
	if protocol ~= nil then
		while a ~= nil and a.ai_protocol ~= protocol do
			a = a.ai_next
		end
	end
	local addr = ffi.new('struct sockaddr_in [1]')
	if a ~= nil then
		local sinp = ffi.cast('struct sockaddr_in *', a.ai_addr)
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
	new = function(self)
		self.fd		= -1
		self.port	= -1
	end,

	setsockopt = function(self, level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		valuelen = valuelen or ffi.sizeof(value)
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
		valuelen = valuelen or ffi.sizeof(value)
		return C.getsockopt(self.fd, level, option, value, valuelen)
	end,

	nonblock = function(self)
		if self.fd < 0 then
			return -1
		end
		local ret = C.fcntl(self.fd, fcntl.S_GETFL)
		return C.fcntl(self.fd, bor(ret, fcntl.O_NONBLOCK))
	end,

	reuseaddr = function(self)
		local value = ffi.new('int[1]', 1)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_REUSEADDR, value)
	end,

	rcvbuf = function(self, size)
		local value = ffi.new('int[1]', size)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVBUF, value)
	end,

	sndbuf = function(self, size)
		local value = ffi.new('int[1]', size)
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_SNDBUF, value)
	end,

	rcvtimeo = function(self, timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = ffi.new('struct timeval[1]', {{sec, frac*1e6}})
		return self:setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVTIMEO, tv, ffi.sizeof(tv[0]))
	end,

	bind = function(self, address, port)
		local addr = socket.getaddrinfo(address, port)
		local addrp = ffi.cast('struct sockaddr *', addr)
		local rc = C.bind(self.fd, addrp, ffi.sizeof(addr[0]))
		if rc < 0 then
			return nil, socket.syserror('bind')
		end
		return rc
	end,

	recv = function(self, buf, len)
		return C.recv(self.fd, buf, len, 0)
	end,

	send = function(self, buf, len)
		return C.send(self.fd, buf, len, 0)
	end,

})

socket.TCP = Class(socket.Socket, {
	new = function(self)
		socket.Socket.new(self)
		self.fd = C.socket(sys_socket.AF_INET,
				sys_socket.SOCK_STREAM, 0)
		if self.fd < 0 then
			return nil, socket.syserror("socket")
		end
	end,

	listen = function(self, backlog)
		local rc = C.listen(self.fd, backlog or 5)
		if rc < 0 then
			return nil, socket.syserror('listen')
		end
		return rc
	end,

	accept = function(self, timeout)
		local from	= ffi.new('struct sockaddr_in[1]')
		local fromp	= ffi.cast('struct sockaddr *', from)
		local size	= ffi.new('socklen_t[1]', ffi.sizeof(from))
		self:rcvtimeo(timeout)
		local rc = C.accept(self.fd, fromp, size)
		return rc, from[0]
	end,

	connect = function(self, host, port)
		local addr	= socket.getaddrinfo(host, port)
		local addrp	= ffi.cast('struct sockaddr *', addr)
		local size	= ffi.sizeof(addr)
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
	end,

	recvfrom = function(self, buf, len)
		local from	= ffi.new('struct sockaddr_in[1]')
		local fromp	= ffi.cast('struct sockaddr *', from)
		local size	= ffi.new('uint32_t[1]', ffi.sizeof(from))
		local ret = C.recvfrom(self.fd, buf, len, 0, fromp, size)
		return ret, from[0]
	end,

	sendto = function(self, buf, len, addr)
		local addrp	= ffi.cast('struct sockaddr *', addr)
		return C.sendto(self.fd, buf, len, 0, addrp, ffi.sizeof(addr))
	end,

	add_membership = function(self, addr, port)
		addr		= socket.getaddrinfo(addr, port)
		local imreq	= ffi.new('struct ip_mreq[1]')
		imreq.imr_multiaddr = addr
		return self:setsockopt(netinet_in.IPPROTO_IP,
				netinet_in.IP_ADD_MEMBERSHIP,
				imreq, ffi.sizeof(imreq))
	end,

	drop_membership = function(self, addr, port)
		addr		= socket.getaddrinfo(addr, port)
		local imreq	= ffi.new('struct ip_mreq[1]')
		imreq.imr_multiaddr = addr
		return self:setsockopt(netinet_in.IPPROTO_IP,
				netinet_in.IP_DROP_MEMBERSHIP,
				imreq, ffi.sizeof(imreq))
	end,
})

local function main()
end

if is_main() then
	main()
else
	return socket
end

