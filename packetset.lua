--
-- u s e f u l / p a c k e t s e t . l u a
--

-- vim:ft=lua
module(..., package.seeall)

local ffi		= require('ffi')
local C = ffi.C

local sys_socket	= require('posix.sys.socket')

local argparse		= require('useful.argparse')
local mmalloc		= require('useful.mmalloc')

sprintf = string.format

function fprintf(out, fmt, ...)
	out:write(sprintf(fmt, ...))
end

function printf(fmt, ...)
	fprintf(io.stdout, fmt, ...)
end

function perror(msg)
	fprintf(io.stderr, '%s failed: errno=%d %s\n', msg, ffi.errno(),
		ffi.string(C.strerror(ffi.errno())))
end

IOV_MAX=1024

function PacketSet(packet_size, npackets)
	npackets = npackets or IOV_MAX
	npackets = math.min(npackets, IOV_MAX)
	local self = {
		npackets	= npackets,
		msgs		= ffi.new("mmsghdr_t[?]", npackets),
		iovecs		= ffi.new("iovec_t[?]", npackets),
	}
	self.buf = ffi.cast('char *', mmalloc.mmalloc(packet_size * npackets))
	for i=0,npackets-1 do
		local iov_base = self.buf + packet_size * i
		self.iovecs[i].iov_base		= ffi.cast('void *', iov_base)
		self.iovecs[i].iov_len		= packet_size
		self.msgs[i].msg_hdr.msg_iov	= self.iovecs + i
		self.msgs[i].msg_hdr.msg_iovlen	= 1
	end

	function self.set_iov_len(len)
		for i=0,npackets-1 do
			iovecs[i].iov_len = len or packet_size
		end
	end

	function self.iov_len_from_mmsg()
		for i=0,npackets-1 do
			iovecs[i].iov_len = self.msgs[i].msg_len
		end
	end

	function self.recvmmsg(fd, offset, count)
		local msgs = self.msgs + offset
		rc = C.recvmmsg(fd, msgs, count or npackets, 0, nil)
		if rc < 0 then
			perror('recvmmsg()')
		end
		return rc
	end

	function self.sendmmsg(fd, offset, count)
		local msgs = self.msgs + offset
		rc = C.sendmmsg(fd, msgs, count or npackets, 0)
		if rc < 0 then
			perror('sendmmsg()')
		end
		return rc
	end

	function self.writev(fd, offset, count)
		local iovecs = self.iovecs + offset
		rc = C.writev(fd, iovecs, count or npackets)
		if rc < 0 then
			perror('writev()')
		end
		return rc
	end

	function self.readv(fd, offset, count)
		local iovecs = self.iovecs + offset
		rc = C.readv(fd, iovecs, count or npackets)
		if rc < 0 then
			perror('readv()')
		end
		return rc
	end

	return self
end

