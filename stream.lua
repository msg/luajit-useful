--
-- u s e f u l / s t r e a m . l u a
--

-- vim:ft=lua
local function is_main()
	return debug.getinfo(4) == nil
end

if not is_main() then
	module(..., package.seeall)
end

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
local class	= require('useful.class')
local Class	= class.Class

local min = math.min

local printf = function(...) io.stdout:write(string.format(...)) end

NOFD = -1 -- when the Stream has no file descriptor

Stream = Class({
	new = function(self, fd, size, timeout, unget_size)
		unget_size = unget_size or 1
		self.fd		= fd
		self.size	= size
		self.unget_size	= unget_size
		self.in_buffer	= ffi.new('char[?]', size + unget_size + 1)
		self.out_buffer	= ffi.new('char[?]', size)
		self.out_next	= ffi.cast('char *', self.out_buffer)
		self:set_timeout(timeout)
		self:flush_read()
	end,

	set_timeout = function(self, timeout)
		if self.fd ~= NOFD then
			local fl
			fl = bor(C.fcntl(self.fd, fcntl.F_GETFL), fcntl.O_NONBLOCK)
			C.fcntl(self.fd, fcntl.F_SETFL, fl)
		end
		self.timeout = timeout
	end,

	reopen = function(self, fd)
		if self.fd ~= NOFD then
			self:close()
		end
		self.out_next	= self.out_buffer
		self.fd		= fd
		if fd ~= NOFD then
			self:set_timeout(self.timeout)
		end
		return 0
	end,

	close = function(self)
		self:flush()
		return C.close(self.fd)
	end,

	flush_read = function(self)
		self.in_next	= self.in_buffer + self.unget_size
		self.in_end	= self.in_next
	end,

	flush_write = function(self)
		local rc = 0
		local p = self.out_buffer
		while p < self.out_next do
			rc = self:stream_write(p, self.out_next - p)
			if rc <= 0 then
				return rc
			end
			p = p + rc
		end
		self.out_next = self.out_buffer
		return rc
	end,

	flush = function(self)
		self:flush_read()
		self:flush_write()
	end,

	stream_poll = function(self, fd, events, timeout)
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
	end,

	stream_read = function(self, buf, len)
		local rc
		rc = self:stream_poll(self.fd, poll.POLLIN, self.timeout)
		if rc < 0 then
			return rc
		end
		return C.read(self.fd, buf, len)
	end,

	stream_write = function(self, buf, len)
		local rc
		rc = self:stream_poll(self.fd, poll.POLLOUT, self.timeout)
		if rc < 0 then
			return rc
		end
		return C.write(self.fd, buf, len)
	end,

	stream_close = function(self)
		return C.close(self.fd)
	end,

	read_more = function(self)
		local rc = -1
		self.in_next	= self.in_buffer + self.unget_size
		self.in_end	= self.in_next
		while true do
			rc = self:stream_read(self.in_next, self.size)
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
	end,

	getch = function(self)
		if self.in_next == self.in_end then
			if self:read_more() < 0 then
				return -1
			end
		end
		local c		= self.in_next[0]
		self.in_next	= self.in_next + 1
		return c
	end,

	ungetch = function(self, c)
		if self.in_next == self.in_buffer then
			return -1
		end
		self.in_next	= self.in_next - 1
		self.in_next[0]	= c
		return c
	end,

	read = function(self, buf, len)
		local rc = 0
		local p = buf
		local e = p + len
		while p < e do
			if self.in_next ~= self.in_end then
				local n
				n = min(self.in_end - self.in_next, e - p)
				C.memcpy(p, self.in_next, n)
				p		= p + n
				self.in_next	= self.in_next + n
			else
				rc = self:read_more()
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
	end,

	read_delims = function(self, buf, len, delims)
		if len == 0 then
			return 0
		end

		local rc	= 0
		local p		= buf
		local e		= p + len - 1 -- for \0
		while p < e do
			if self.in_next ~= self.in_end then
				local n, spn
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
				rc = self:read_more()
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
	end,

	unread_space = function(self)
		return self.in_next - self.in_buffer
	end,

	unread = function(self, buf, len)
		local p = buf
		local n = min(self.in_next - self.in_buffer, len)
		if n <= 0 then
			return -1
		end
		self.in_next = self.in_next - n
		C.memcpy(self.in_next, p + len - n, n)
		return n
	end,

	write = function(self, buf, len)
		local rc	= 0
		local p		= buf
		local e		= p + len
		local out_end	= self.out_buffer + self.size
		while p < e do
			if out_end == self.out_next then
				rc = self:flush_write()
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
	end,

	writef = function(self, fmt, ...)
		local rc
		local buf = string.format(fmt, ...)
		return self:write(buf, #buf)
	end,

	readline = function(self, buf, len)
		local rc, c, d

		-- -3 below because eol could be two chars plus the terminating \0.
		rc = self:read_delims(buf, len-3, "\r\n");
		if rc <= 0 then
			return rc
		end
		if string.char(buf[rc-1]) == '\r' then
			d = self:getch()
			if string.char(d) ~= '\n' then
				self:ungetch(d)
			else
				buf[rc] = d
				rc = rc + 1
			end
		end

		buf[rc] = 0 -- terminate for safety
		return rc;
	end,
})

TCPStream = Class(Stream, {
	new = function(self, fd, size, timeout, unget_size)
		self.tcp = socket.TCP() -- must be first, Stream:new calls set_timeout()
		Stream:new(self, fd, size, timeout, unget_size)
	end,

	set_timeout = function(self, timeout)
		Stream:set_timeout(self, timeout)
		self.tcp.fd = self.fd
		self.tcp:rcvtimeo(timeout)
	end,

	stream_write = function(self, buf, len)
		-- no polling needed because of SO_RCV_TIMEO
		return C.write(self.fd, buf, len)
	end,
})

local function main()
end

if is_main() then
	main()
end

