--
-- s c h e d u l e r / b u f f e r . l u a
--
local ffi	= require('ffi')
local  C	=  ffi.C
local  copy	=  ffi.copy

local class	= require('useful.class')
local  Class 	=  class.Class
local range	= require('useful.range')
local  uint8	=  range.uint8

local buffer = { }

local NL = string.byte('\n')

local function find_nl(r8)
	r8 = r8:save()
	while not r8:empty() and r8:get_front() ~= NL do
		r8:pop_front()
	end
	return r8
end
buffer.find_nl = find_nl

buffer.Buffer = Class({
	new = function(self, size)
		self.buffer	= uint8.vla(size)
		self.free	= uint8.from_vla(self.buffer)
		self.avail	= uint8(self.free.front, self.free.front)
	end,

	__len = function(self)
		return #self.avail
	end,

	reset = function(self)
		self.free.front		= self.buffer
		self.avail.front	= self.buffer
		self.avail.back		= self.avail.front
	end,

	copy_to = function(self, to_buffered)
		local r			= to_buffered.free:save()
		local n			= math.min(#self.avail, #r)
		copy(r.front, self.avail.front, n)
		to_buffered.free:pop_front(n)
		self.avail:pop_front(n)
		to_buffered.avail.back	= to_buffered.free.front + n
		r.back			= r.front + n
		return r
	end,

	flush_read = function(self)
		self:reset()
	end,

	read_more = function(self, sock, nbytes)
		local n = sock:recv(self.free.front, nbytes, C.MSG_DONTWAIT)
		self.avail.back = self.avail.back + n
		self.free:pop_front(n)
		return tonumber(n)
	end,

	read = function(self, sock, nbytes)
		local avail = self.avail:save()
		if nbytes >= #avail then
			nbytes		= nbytes - #avail
			avail.back	= avail.front + #avail
		end
		nbytes = math.min(nbytes, #self.free)
		while nbytes > 0 do
			local n		= self:read_more(sock, nbytes)
			n		= math.min(n, nbytes)
			avail.back	= avail.back + n
			nbytes		= nbytes - n
		end
		self.avail:pop_front(#avail)
		return avail
	end,

	read_line = function(self, sock)
		local line = self.avail:save()
		while true do
			line = find_nl(line)
			if line:empty() then
				if #self.free == 0 then
					return line
				end
				local n		= #self.free
				n		= self:read_more(sock, n)
				line.back	= line.back + n
			else
				line.back	= line.front + 1
				line.front	= self.avail.front
				self.avail:pop_front(#line)
				return line
			end
		end
	end,

	flush_write = function(self, sock)
		local nbytes = 0
		while #self.avail > 0 do
			local n = sock:send(self.avail.front, #self.avail)
			nbytes = nbytes + n
			self.avail:pop_front(n)
		end
		self:reset()
		return nbytes
	end,

	write = function(self, data)
		local r			= self.free:save()
		local n			= math.min(#data, #r)
		copy(r.front, data, n)
		self.free:pop_front(n)
		self.avail.back		= self.avail.back + n
		r.back			= r.front + n
		return r
	end,

	writef = function(self, ...)
		local r			= self.free:save()
		local n			= C.snprintf(r.front, #r, ...)
		if n > #r then
			return 0 -- cannot satisfy the writef with this buffer.
		end
		self.free:pop_front(n)
		self.avail.back		= self.avail.back + n
		r.back			= r.front + n
		return r
	end,
})

return buffer
