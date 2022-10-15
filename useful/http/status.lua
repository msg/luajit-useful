#!/usr/bin/luajit
--
-- h t t p / s t a t u s . l u a
--
local status = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  cast	=  ffi.cast

		  require('posix.stdio')
		  require('posix.unistd')

local class	= require('useful.class')
local  Class	=  class.Class
local range	= require('useful.range')
local rbuffer	= require('useful.range.buffer')
local  Buffer	=  rbuffer.Buffer
local rstring	= require('useful.range.string')
local  is_end_of_line	=  rstring.is_end_of_line
local  is_whitespace	=  rstring.is_whitespace
local  rstrip		=  rstring.rstrip
local  skip_ws		=  rstring.skip_ws

local do_header	= rstring.make_until(rstring.COLON)
status.do_header = do_header

local char_range_array	= ffi.typeof('$[?]', range.int8)
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
			return self.sock:recv(p, sz, C.MSG_DONTWAIT)
		end
		local write = function(p, sz)
			return self.sock:send(p, sz)
		end
		self.write	= write
		self.buffer	= Buffer(size, read, write)
		self.header_buf	= Buffer(header_size or size, read, write)
		self.header	= char_range_array(MAXENTRIES)
	end,

	reset = function(self)
		self.buffer:reset()
		self.header_buf:reset()
		self.status	= nil
		self.nheader	= 0
	end,

	set_sock = function(self, sock)
		self.sock = sock
	end,

	recv_status = function(self)
		self.status = rstrip(self.buffer:read_line())
	end,

	recv_header = function(self)
		local header = self.header
		local nheader = 0
		while nheader < MAXENTRIES do
			local line = self.buffer:read_line()
			local c = line:get_front()
			if is_end_of_line(c) then
				break
			elseif is_whitespace(c) then
				header[nheader-1].back = line.back
			else
				header[nheader] = line
				nheader = nheader + 1
			end
		end
		self.nheader = nheader
	end,

	recv = function(self)
		self:recv_status()
		self:recv_header()
	end,

	avail = function(self)
		return self.buffer.avail:size()
	end,

	read = function(self, n)
		return self.buffer:read(n)
	end,

	read_line = function(self)
		return self.buffer:read_line()
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
		self.header[self.nheader] = r
		self.nheader = self.nheader + 1
		return r
	end,

	send_header = function(self)
		self.header_buf:write('\r\n', 2)
		return self.header_buf:flush_write()
	end,

	send_status = function(self)
		return self.buffer:flush_write()
	end,

	send_request = function(self, method, path)
		self.buffer:writef('%s %s HTTP/1.1\r\n', method, path)
		local n = self:send_status()
		return n + self:send_header()
	end,

	send_response = function(self, code, message)
		code = cast('int', code)
		self.buffer:writef('HTTP/1.1 %d %s\r\n', code, message)
		local n = self:send_status()
		return n + self:send_header()
	end,
})
status.Status = Status

return status
