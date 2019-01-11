--
-- u s e f u l / p a c k e t s e t . l u a
--
local packetset = { }

local ffi		= require('ffi')
local C = ffi.C

local sys_socket	= require('posix.sys.socket')

local argparse		= require('useful.argparse')
local mmalloc		= require('useful.mmalloc')

local class		= require('useful.class')
local Class		= class.Class

local sprintf = string.format

local function fprintf(out, fmt, ...)
	out:write(sprintf(fmt, ...))
end

local function printf(fmt, ...)
	fprintf(io.stdout, fmt, ...)
end

local function perror(msg)
	fprintf(io.stderr, '%s failed: errno=%d %s\n', msg, ffi.errno(),
		ffi.string(C.strerror(ffi.errno())))
end

packetset.IOV_MAX = 1024

packetset.PacketSet = Class({
	new = function(self, packet_size, npackets)
		npackets = npackets or IOV_MAX
		npackets = math.min(npackets, IOV_MAX)
		self.npackets	= npackets
		self.msgs	= ffi.new("mmsghdr_t[?]", npackets)
		self.iovecs	= ffi.new("iovec_t[?]", npackets)
		local buf	=  mmalloc.mmalloc(packet_size * npackets)
		self.buf = ffi.cast('char *', buf)
		for i=0,npackets-1 do
			local iov_base = self.buf + packet_size * i
			self.iovecs[i].iov_base	= ffi.cast('void *', iov_base)
			self.iovecs[i].iov_len = packet_size
			self.msgs[i].msg_hdr.msg_iov = self.iovecs + i
			self.msgs[i].msg_hdr.msg_iovlen	= 1
		end
	end,

	set_iov_len = function(self, len)
		for i=0,npackets-1 do
			iovecs[i].iov_len = len or packet_size
		end
	end,

	iov_len_from_mmsg = function(self)
		for i=0,npackets-1 do
			iovecs[i].iov_len = self.msgs[i].msg_len
		end
	end,

	recvmmsg = function(self, fd, offset, count)
		local msgs = self.msgs + offset
		rc = C.recvmmsg(fd, msgs, count or npackets, 0, nil)
		if rc < 0 then
			perror('recvmmsg()')
		end
		return rc
	end,

	sendmmsg = function(self, fd, offset, count)
		local msgs = self.msgs + offset
		rc = C.sendmmsg(fd, msgs, count or npackets, 0)
		if rc < 0 then
			perror('sendmmsg()')
		end
		return rc
	end,

	writev = function(self, fd, offset, count)
		local iovecs = self.iovecs + offset
		rc = C.writev(fd, iovecs, count or npackets)
		if rc < 0 then
			perror('writev()')
		end
		return rc
	end,

	readv = function(self, fd, offset, count)
		local iovecs = self.iovecs + offset
		rc = C.readv(fd, iovecs, count or npackets)
		if rc < 0 then
			perror('readv()')
		end
		return rc
	end,
})

return packetset
