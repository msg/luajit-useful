--
-- b u f f e r . l u a
--
local ffi	= require('ffi')
local  C	=  ffi.C
local  copy	=  ffi.copy

local class	= require('useful.class')
local  Class 	=  class.Class
local range	= require('useful.range')
local  int8	=  range.int8

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
		self.buffer	= int8.vla(size)
		self.free	= int8.from_vla(self.buffer)
		self.avail	= int8(self.free.front, self.free.front)
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

	read_more = function(self, read_func, nbytes)
		local n = read_func(self.free.front, nbytes)
		self.avail.back = self.avail.back + n
		self.free:pop_front(n)
		return tonumber(n)
	end,

	read = function(self, read_func, nbytes)
		local avail = self.avail:save()
		if nbytes >= #avail then
			nbytes		= nbytes - #avail
			avail.back	= avail.front + #avail
		end
		nbytes = math.min(nbytes, #self.free)
		assert(nbytes < #self.free + #self.avail)
		while nbytes > #self.avail do
			self:read_more(read_func, nbytes)
		end
		avail.back = avail.front + nbytes
		self.avail:pop_front(#avail)
		return avail
	end,

	read_line = function(self, read_func)
		while true do
			local line = find_nl(self.avail)
			if line:empty() then
				if #self.free == 0 then
					return line
				end
				self:read_more(read_func, #self.free)
			else
				line.back	= line.front + 1
				line.front	= self.avail.front
				self.avail:pop_front(#line)
				return line
			end
		end
	end,

	flush_write = function(self, write_func)
		local nbytes = 0
		while #self.avail > 0 do
			local n = write_func(self.avail.front, #self.avail)
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
