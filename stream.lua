--
-- s t r e a m . l u a
--

-- vim:ft=lua
module(..., package.seeall)

local ffi	= require('ffi')
local C		= ffi.C

local bit	= require('bit')
local bnot	= bit.bnot
local bor	= bit.bor
local band	= bit.band
local lshift	= bit.lshift
local rshift	= bit.rshift

local sys_types = require('posix.sys.types')
local unistd	= require('posix.unistd')
local poll	= require('posix.poll')
local fcntl	= require('posix.fcntl')
local pstring	= require('posix.string')

local socket	= require('useful.socket')

local min = math.min

local printf = function(...) io.stdout:write(string.format(...)) end

NOFD = -1 -- when the Stream has no file descriptor

function Stream(fd, size, timeout, unget_size)
	unget_size = unget_size or 1
	local self = {
		fd		= fd,
		size		= size,
		unget_size	= unget_size,
	}
	self.in_buffer	= ffi.new('char[?]', size + unget_size + 1)
	self.out_buffer	= ffi.new('char[?]', size)
	self.out_next	= ffi.cast('char *', self.out_buffer)

	function self.set_timeout(timeout)
		if self.fd ~= NOFD then
			local fl = bor(C.fcntl(self.fd, fcntl.F_GETFL),
					fcntl.O_NONBLOCK)
			C.fcntl(self.fd, fcntl.F_SETFL, fl)
		end
		self.timeout = timeout
	end

	function self.reopen(fd)
		if self.fd ~= NOFD then
			self.close()
		end
		self.out_next	= self.out_buffer
		self.fd		= fd
		if fd ~= NOFD then
			self.set_timeout(self.timeout)
		end
		return 0
	end

	function self.close()
		self.flush()
		return C.close(self.fd)
	end

	function self.flush_read()
		self.in_next	= self.in_buffer + self.unget_size
		self.in_end	= self.in_next
	end

	function self.flush_write()
		local rc = 0
		local p = self.out_buffer
		while p < self.out_next do
			rc = self.stream_write(p, self.out_next - p)
			if rc <= 0 then
				return rc
			end
			p = p + rc
		end
		self.out_next = self.out_buffer
		return rc
	end

	function self.flush()
		self.flush_read()
		self.flush_write()
	end

	function self.stream_poll(fd, events, timeout)
		local rc
		local pfd	= ffi.new('struct pollfd[1]')
		pfd[0].fd	= fd
		pfd[0].events	= events
		rc = C.poll(pfd, 1, timeout * 1000)
		if rc <= 0 then
			errno = EAGAIN
			return rc
		end
		return 0
	end

	function self.stream_read(buf, len)
		local rc
		rc = self.stream_poll(self.fd, poll.POLLIN, self.timeout)
		if rc < 0 then
			return rc
		end
		return C.read(self.fd, buf, len)
	end

	function self.stream_write(buf, len)
		local rc
		rc = self.stream_poll(self.fd, poll.POLLOUT, self.timeout)
		if rc < 0 then
			return rc
		end
		return C.write(self.fd, buf, len)
	end

	function self.stream_close()
		return C.close(self.fd)
	end

	function self.read_more()
		local rc = -1
		self.in_next	= self.in_buffer + self.unget_size
		self.in_end	= self.in_next
		while true do
			rc = self.stream_read(self.in_next, self.size)
			if rc < 0 then
				break
			end
			self.in_end = self.in_next + rc
			self.in_end[0] = 0
			if errno == EINTR then
				return rc
			end
		end
		return rc
	end

	function self.getch()
		if self.in_next == self.in_end then
			if self.read_more() < 0 then
				return -1
			end
		end
		local c		= self.in_next[0]
		self.in_next	= self.in_next + 1
		return c
	end

	function self.ungetch(c)
		if self.in_next == self.in_buffer then
			return -1
		end
		self.in_next	= self.in_next - 1
		self.in_next[0]	= c
		return c
	end

	function self.read(buf, len)
		local rc = 0
		local p = buf
		local e = p + len
		local n
		while p < e do
			if self.in_next ~= self.in_end then
				n = min(self.in_end - self.in_next, e - p)
				C.memcpy(p, self.in_next, n)
				p		= p + n
				self.in_next	= self.in_next + n
			else
				rc = self.read_more()
				if rc <= 0 then
					break
				end
			end
		end
		if p == buf then
			return rc
		else
			return p - buf
		end
	end

	function self.read_delims(buf, len, delims)
		local rc	= 0
		local p		= buf
		local e		= p + len - 1 -- for \0
		local n, spn
		if len == 0 then
			return 0
		end

		while p < e do
			if self.in_next ~= self.in_end then
				n	= min(self.in_end - self.in_next, e - p)
				spn	= C.strcspn(self.in_next, delims)
				if spn < n then
					n = spn + 1
				end
				C.memcpy(p, self.in_next, n)
				p		= p + n
				self.in_next	= self.in_next + n
				if n == spn + 1 then
					break
				end
			else
				rc = self.read_more()
				if rc <= 0 then
					break
				end
			end
		end
		p[0] = 0
		if p == buf then
			return rc
		else
			return p - buf
		end
	end

	function self.unread_space()
		return self.in_next - self.in_buffer
	end

	function self.unread(buf, len)
		local p = buf
		local n = min(self.in_next - self.in_buffer, len)
		if n <= 0 then
			return -1
		end
		self.in_next = self.in_next - n
		C.memcpy(self.in_next, p + len - n, n)
		return n
	end

	function self.write(buf, len)
		local rc	= 0
		local p		= buf
		local e		= p + len
		local out_end	= self.out_buffer + size
		while p < e do
			if out_end == self.out_next then
				rc = self.flush_write()
				if rc < 0 then
					return rc
				end
			end
			rc		= min(e - p, out_end - self.out_next)
			C.memcpy(self.out_next, p, rc)
			self.out_next	= self.out_next + rc
			p		= p + rc
		end
		return p - buf
	end

	function self.writef(fmt, ...)
		local rc
		local buf = string.format(fmt, ...)
		return self.write(buf, #buf)
	end

	function self.readline(buf, len)
		local rc, c, d

		-- -3 below because eol could be two chars plus the terminating \0.
		rc = self.read_delims(buf, len-3, "\r\n");
		if rc <= 0 then
			return rc
		end
		if string.char(buf[rc-1]) == '\r' then
			d = self.getch()
			if string.char(d) ~= '\n' then
				self.ungetch(d)
			else
				buf[rc] = d
				rc = rc + 1
			end
		end

		buf[rc] = 0 -- terminate for safety
		return rc;
	end

	self.set_timeout(timeout)
	self.flush_read()
	return self
end

function TCPStream(fd, size, timeout, unget_size)
	local self = Stream(fd, size, timeout, unget_size)
	local self.tcp = tcp()

	function self.set_timeout(timeout)
		self.tcp.fd = self.fd
		self.rcvtimeo(timeout)
	end

	function self.stream_write(buf, len)
		-- no polling needed because of SO_RCV_TIMEO
		return C.write(self.fd, buf, len)
	end

	return self
end

