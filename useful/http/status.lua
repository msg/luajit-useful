#!/usr/bin/luajit
--
-- h t t p / s t a t u s . l u a
--
local status = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast

			  require('posix.stdio')
			  require('posix.unistd')

local class		= require('useful.class')
local  Class		=  class.Class
local protect_		= require('useful.protect')
local  unprotect1	=  protect_.unprotect1
local range		= require('useful.range')
local  char		=  range.char
local buffer		= require('useful.range.buffer')
local  Buffer		=  buffer.Buffer
local rstring		= require('useful.range.string')
local  is_end_of_line	=  rstring.is_end_of_line
local  is_whitespace	=  rstring.is_whitespace
local  rstrip		=  rstring.rstrip
local  skip_ws		=  rstring.skip_ws
local stdio		= require('useful.stdio')
local  printf		=  stdio.printf

local do_header	= rstring.make_until(rstring.COLON)
status.do_header = do_header

local char_range_array	= ffi.typeof('$[?]', char)
status.char_range_array	= char_range_array

local MAXENTRIES	= 64
status.MAXENTRIES	= MAXENTRIES

status.OK			= 200
status.MOVED_PERMANENTLY	= 301
status.BAD_REQUEST		= 400
status.UNAUTHORIZED		= 401
status.FORBIDDEN		= 403
status.NOT_FOUND		= 404
status.INTERNAL_SERVER_ERROR	= 500
status.NOT_IMPLEMENTED		= 501
status.UNAVAILABLE		= 503

status.code_strings = {
	[status.OK]			= 'OK',
	[status.MOVED_PERMANENTLY]	= "Moved Permanently",
	[status.BAD_REQUEST]		= 'Bad Request',
	[status.UNAUTHORIZED]		= 'Unauthorized',
	[status.FORBIDDEN]		= 'Forbidden',
	[status.NOT_FOUND]		= 'Not Found',
	[status.INTERNAL_SERVER_ERROR]	= 'Internal Server Error',
	[status.NOT_IMPLEMENTED]	= 'Not Implemented',
	[status.UNAVAILABLE]		= 'Unavailable',
}

local Status = Class({
	new = function(self, size, header_size)
		local read = function(p, sz)
			return self.sock:recv(p, sz)
		end
		local write = function(p, sz)
			--print('write <'..ffi.string(p, sz)..'>')
			return self.sock:send(p, sz)
		end
		self.buffer	= Buffer(size, read, write)
		self.header_buf	= Buffer(header_size or size, read, write)
		self.header	= char_range_array(MAXENTRIES)
	end,

	flush = function(self)
		self.buffer:flush(true)
		self.header_buf:flush(true)
		self.status	= nil
		self.nheader	= 0
	end,

	setup = function(self, sock)
		self:flush()
		self.sock = sock
	end,

	avail = function(self)
		return self.buffer.avail:size()
	end,

	read = unprotect1(function(self, n)
		return self.buffer:read(n)
	end),

	read_line = unprotect1(function(self)
		return self.buffer:read_line()
	end),

	recv_status = function(self)
		self.status = rstrip(self:read_line())
	end,

	recv_header = function(self)
		local header = self.header
		local nheader = 0
		while nheader < MAXENTRIES do
			local line = self:read_line()
			local c = line:get_front()
			if is_end_of_line(c) then
				break
			elseif is_whitespace(c) then
				header[nheader-1].back	= line.back
			else
				header[nheader]		= line
				nheader			= nheader + 1
			end
		end
		self.nheader = nheader
	end,

	recv = function(self)
		self:recv_status()
		self:recv_header()
	end,

	get = function(self, name, default)
		local namep = cast('const char *', name)
		local namesz = #name
		for i=0,self.nheader-1 do
			local headerp = self.header[i].front
			local rc = C.strncasecmp(namep, headerp, namesz)
			if rc == 0 then
				local r = self.header[i]:save()
				do_header(r)
				if not r:empty() then
					r = rstrip(skip_ws(r))
					return r:to_string()
				end
			end
		end
		return default or ''
	end,

	set = function(self, name, value)
		local r = self.header_buf:write(name..': '..value..'\r\n')
		rstrip(r)
		--print('r='..tostring(r)..'=')
		self.header[self.nheader] = r
		self.nheader = self.nheader + 1
		return r
	end,

	flush_status = unprotect1(function(self)
		return self.buffer:flush_write()
	end),

	flush_header = unprotect1(function(self)
		return self.header_buf:flush_write()
	end),

	write = function(self, buf, len)
		return self.header_buf.write_func(buf, len)
	end,

	send_status_and_header = function(self)
		local n = self:flush_status()
		self.header_buf:write('\r\n', 2)
		n = n + self:flush_header()
		return n
	end,

	send_request = function(self, method, path)
		self.buffer:writef('%s %s HTTP/1.1\r\n', method, path)
		return self:send_status_and_header()
	end,

	send_response = function(self, code, message)
		message = message or status.code_strings[code] or 'Unknown'
		self.buffer:writef('HTTP/1.1 %d %s\r\n', code, message)
		return self:send_status_and_header()
	end,

	dump = function(self)
		if self.status then
			local line = self.status
			printf('status=<%s>\n', line.s)
		end
		for i=0,self.nheader-1 do
			local header = self.header[i]
			rstrip(header)
			printf('<%s>\n', header.s)
		end
	end,
})
status.Status = Status

return status
