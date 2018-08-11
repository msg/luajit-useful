--
-- u s e f u l / s o c k e t . l u a
--
local function is_main()
	return debug.getinfo(4) == nil
end

if not is_main() then
	module(..., package.seeall)
end

local ffi		= require('ffi')
local C			= ffi.C

local bit		= require('bit')
local bor		= bit.bor

local unistd		= require('posix.unistd')
local fcntl		= require('posix.fcntl')
local sys_types		= require('posix.sys.types')
local sys_time		= require('posix.sys.time')
local sys_socket	= require('posix.sys.socket')
local posix_string	= require('posix.string')
local arpa_inet		= require('posix.arpa.inet')
local netdb		= require('posix.netdb')
local netinet_in	= require('posix.netinet.in')
local netinet_tcp	= require('posix.netinet.tcp')
local C = ffi.C

local sprintf		= string.format
local printf		= function(...) io.stdout:write(sprintf(...)) end

function syserror(call)
	return sprintf("%s: %s\n", call, ffi.string(C.strerror(ffi.errno())))
end

function getaddrinfo(host, port, protocol)
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
	C.freeaddrinfo(ai[0])
	ai = nil
	return addr
end


function socket()
	local self = {
		fd	= -1,
		port	= -1,
	}

	function self.setsockopt(level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		local valuelen = valuelen or ffi.sizeof(value)
		local rc = C.setsockopt(self.fd, level, option, value, valuelen)
		if rc < 0 then
			return nil, syserror('setsockopt')
		end
		return rc
	end

	function self.getsockopt(level, option, value, valuelen)
		if self.fd < 0 then
			return -1
		end
		local valuelen = valuelen or ffi.sizeof(value)
		return C.getsockopt(self.fd, level, option, value, valuelen)
	end

	function self.nonblock()
		if self.fd < 0 then
			return -1
		end
		local ret = C.fcntl(self.fd, fcntl.S_GETFL)
		return C.fcntl(self.fd, bor(ret, fcntl.O_NONBLOCK))
	end

	function self.reuseaddr()
		local value = ffi.new('int[1]', 1)
		return self.setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_REUSEADDR, value)
	end

	function self.rcvbuf(size)
		local value = ffi.new('int[1]', size)
		return self.setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVBUF, value)
	end

	function self.sndbuf(size)
		local value = ffi.new('int[1]', size)
		return self.setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_SNDBUF, value)
	end

	function self.rcvtimeo(timeout)
		local sec, frac = math.modf(timeout, 1.0)
		local tv = ffi.new('struct timeval[1]', {{sec, frac*1e6}})
		return self.setsockopt(sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVTIMEO, tv, ffi.sizeof(tv[0]))
	end

	function self.bind(address, port)
		local addr = getaddrinfo(address, port)
		local addrp = ffi.cast('struct sockaddr *', addr)
		local rc = C.bind(self.fd, addrp, ffi.sizeof(addr[0]))
		if rc < 0 then
			return nil, syserror('bind')
		end
		return rc
	end

	return self
end

function tcp()
	local self = socket()

	function self.listen(backlog)
		local rc = C.listen(self.fd, backlog or 5)
		if rc < 0 then
			return nil, syserror('listen')
		end
		return rc
	end

	function self.accept(timeout)
		self.rcvtimeo(timeout)
		local from	= ffi.new('struct sockaddr_in[1]')
		local fromp	= ffi.cast('struct sockaddr *', from)
		local size	= ffi.new('socklen_t[1]', ffi.sizeof(from))
		local rc = C.accept(self.fd, fromp, size)
		return rc, from[0]
	end

	self.fd = C.socket(sys_socket.AF_INET, sys_socket.SOCK_STREAM, 0)
	if self.fd < 0 then
		return nil, syserror("socket")
	end
	return self
end

function udp()
	local self = socket()

	function self.recv(buf, flags)
		return C.recv(self.fd, buf, ffi.sizeof(buf), flags)
	end

	function self.recvfrom(buf, flags)
		local from	= ffi.new('struct sockaddr_in[1]')
		local fromp	= ffi.cast('struct sockaddr *', from)
		local size	= ffi.new('uint32_t[1]', ffi.sizeof(from))
		local ret = C.recvfrom(self.fd, buf, ffi.sizeof(buf),
				flags, fromp, size)
		return ret, from[0]
	end

	function self.send(buf, flags)
		return C.send(self.fd, buf, ffi.sizeof(buf), flags)
	end

	function self.sendto(buf, flags, ip, port)
		local addr	= getaddrinfo(ip, port)
		local addrp	= ffi.cast('struct sockaddr *', addr)
		return C.sendto(self.fd, buf, ffi.sizeof(buf), flags,
				addrp, ffi.sizeof(addr))
	end

	self.fd = C.socket(sys_socket.AF_INET, sys_socket.SOCK_DGRAM, 0)
	if self.fd < 0 then
		return nil, syserror("socket")
	end
	return self
end

function main()
end

if is_main() then
	main()
end

