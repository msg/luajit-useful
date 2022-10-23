--
-- b u f f e r . l u a
--
local  min	=  math.min

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
	new = function(self, size, read_func, write_func)
		self.buffer, self.free = int8.vla(size)
		self.avail	= int8(self.free.front, self.free.front)
		self.read_func	= read_func
		self.write_func	= write_func
	end,

	__len = function(self)
		return #self.avail
	end,

	pop_insert = function(self, n)
		self.free:pop_front(n)
		self.avail:pop_back(-n)
	end,

	flush = function(self, force)
		assert(force or #self.avail == 0, 'available bytes in buffer')
		self.free.front		= self.buffer
		self.avail.front	= self.buffer
		self.avail.back		= self.avail.front
	end,

	flush_write = function(self)
		local nbytes = 0
		local avail = self.avail
		while #avail > 0 do
			local n = self.write_func(avail.front, #avail)
			if n >= 0 then
				nbytes = nbytes + n
				avail:pop_front(n)
			elseif nbytes > 0 then
				return nbytes
			else
				return n
			end
		end
		self:flush()
		return nbytes
	end,

	read_more = function(self, nbytes)
		nbytes = min(nbytes, #self.free)
		local n = self.read_func(self.free.front, nbytes)
		if n > 0 then
			self:pop_insert(n)
		end
		return tonumber(n)
	end,

	read_avail = function(self, n)
		n = n or 1
		assert(n <= #self.avail)
		return self.avail:read_front_size(n or 1)
	end,

	read = function(self, nbytes)
		nbytes = min(nbytes, #self.avail + #self.free)
		while #self.avail < nbytes do
			local rc = self:read_more(nbytes - #self.avail)
			if rc < 0 then
				return nil, rc
			end
		end
		local r8 = self.avail:front_range(nbytes)
		self.avail:pop_front(#r8)
		return r8
	end,

	read_line = function(self)
		local line
		while true do
			line = find_nl(self.avail)
			if not line:empty() then
				break
			elseif #self.free == 0 then
				return self.avail.read_front_size(#self.avail)
			end
			local rc = self:read_more(#self.free)
			if rc < 0 then
				return nil, rc
			end
		end
		line.back	= line.front + 1
		line.front	= self.avail.front
		self.avail:pop_front(#line)
		return line
	end,

	write = function(self, data)
		if type(data) == 'string' then
			data = self.free.from_string(data)
		end
		local nbytes	= min(#data, #self.free)
		local r8	= self.free:front_range(nbytes)
		copy(r8.front, data.front, nbytes)
		self:pop_insert(nbytes)
		return r8
	end,

	writef = function(self, ...)
		local nbytes = C.snprintf(nil, 0, ...)
		assert(nbytes + 1 <= #self.free, 'not enough space to writef')
		local r8	= self.free:front_range(nbytes)
		C.snprintf(r8.front, nbytes+1, ...)
		self:pop_insert(nbytes)
		return r8
	end,
})

return buffer
