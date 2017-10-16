
module(..., package.seeall)

local ffi		= require('ffi')

local unistd		= require('posix.unistd')
local sys_types		= require('posix.sys.types')
local sys_time		= require('posix.sys.time')
local sys_socket	= require('posix.sys.socket')
local posix_string	= require('posix.string')
local arpa_inet		= require('posix.arpa.inet')
local netinet_in	= require('posix.netinet.in')
local netinet_tcp	= require('posix.netinet.tcp')
local C = ffi.C

local sprintf		= string.format
local printf		= function(...) io.stdout:write(sprintf(...)) end

local function syserror(call)
	return sprintf("%s: %s\n", call, ffi.string(C.strerror(ffi.errno())))
end

function TCPSocket(server_port, backlog)
	local self = { }
	local err
	backlog = backlog or 5

	local s = C.socket(sys_socket.AF_INET, sys_socket.SOCK_STREAM, 0)
	if s < 0 then
		return nil, syserror("socket")
	end

	local val = ffi.new('int[1]', {1})
	local rc = C.setsockopt(s, sys_socket.SOL_SOCKET,
				sys_socket.SO_REUSEADDR, val, ffi.sizeof(val))
	if rc < 0 then
		err = syserror("setsockopt SO_REUSEADDR")
		C.close(s)
		return nil, err
	end

	rc = C.setsockopt(s, netinet_in.IPPROTO_TCP,
				netinet_tcp.TCP_NODELAY, val, ffi.sizeof(val))
	if rc < 0 then
		s = syserror("setsockopt TCP_NODELAY")
		C.close(s)
		return nil, s
	end

	if server_port and server_port > 0 then
		local addr_in		= ffi.new('struct sockaddr_in[1]')
		addr_in[0].sin_family	= sys_socket.AF_INET;
		addr_in[0].sin_port	= C.htons(server_port)
		addr_in[0].sin_addr.s_addr = netinet_in.INADDR_ANY
		local addr		= ffi.cast('struct sockaddr *', addr_in)

		rc = C.bind(s, addr, ffi.sizeof(addr[0]))
		if rc < 0 then
			err = syserror("bind")
			C.close(s)
			return nil, err
		end

		rc = C.listen(s, backlog)
		if rc < 0 then
			err = syserror("listen")
			C.close(s)
			return nil, err
		end
	end

	self.fd = s

	function self.accept(timeout_ms)
		timeout_ms	= timeout_ms or 0
		local tv	= ffi.new('struct timeval')
		local from_in	= ffi.new('struct sockaddr_in[1]')
		local from	= ffi.cast('struct sockaddr *', from_in)
		local size	= ffi.new('socklen_t[1]', ffi.sizeof(from_in))
		if timeout_ms > 0 then
			tv.tv_sec	= timeout_ms / 1000
			tv.tv_usec	= (timeout_ms % 1000) * 1000
		else
			tv.tv_sec	= -1
		end
		C.setsockopt(self.fd, sys_socket.SOL_SOCKET,
				sys_socket.SO_RCVTIMEO, tv, size[1])
		local rc = C.accept(self.fd, from, size)
		return rc, from_in[0]
	end

	function self.connect(timeout_ms, addr_in)
		local addr	= ffi.cast('struct sockaddr *', addr_in)
		local rc	= C.connect(self.fd, addr, ffi.sizeof(addr_in))
	end

	return self
end

function main_test()
	local server, err = TCPSocket(12345)
	if server == nil then
		print("error " .. err)
	end
	rc, from = server.accept(10000)
	if rc < 0 then
		print(syserror("accept"))
	end
	printf('rc=%d from=0x%08x:%d\n', rc,
		tonumber(C.ntohl(from.sin_addr.s_addr)),
		tonumber(C.ntohs(from.sin_port)))
	C.write(rc, 'testing\n', 8)
	C.sleep(10)
end

