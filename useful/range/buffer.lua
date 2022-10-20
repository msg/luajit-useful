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
	new = function(self, size, read_func, write_func)
		self.buffer	= int8.vla(size)
		self.free	= int8.from_vla(self.buffer)
		self.avail	= int8(self.free.front, self.free.front)
		self.read_func	= read_func
		self.write_func	= write_func
	end,

	__len = function(self)
		return #self.avail
	end,

	reset = function(self)
		assert(#self.avail == 0)
		self.free.front		= self.buffer
		self.avail.front	= self.buffer
		self.avail.back		= self.avail.front
	end,

	adjust_free_avail = function(self, n)
		self.free:pop_front(n)
		self.avail:pop_back(-n)
	end,

	read_avail = function(self, n)
		n = n or 1
		assert(n <= #self.avail)
		return self.avail:read_front_size(n or 1)
	end,

	flush = function(self)
		self.avail:pop_front(#self.avail)
		self:reset()
	end,

	read_more = function(self, nbytes)
		nbytes = math.min(nbytes, #self.free)
		local n = self.read_func(self.free.front, nbytes)
		if n > 0 then
			self:adjust_free_avail(n)
		end
		return tonumber(n)
	end,

	read = function(self, nbytes)
		nbytes = math.min(nbytes, #self.avail + #self.free)
		while #self.avail < nbytes do
			local rc = self:read_more(nbytes - #self.avail)
			if rc < 0 then
				return nil, rc
			end
		end
		local avail = self.avail:save()
		avail.back = avail.front + nbytes
		self.avail:pop_front(#avail)
		return avail
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

	flush_write = function(self)
		local nbytes = 0
		while #self.avail > 0 do
			local n = self.write_func(self.avail.front, #self.avail)
			if n >= 0 then
				nbytes = nbytes + n
				self.avail:pop_front(n)
			elseif nbytes > 0 then
				return nbytes
			else
				return n
			end
		end
		self:reset()
		return nbytes
	end,

	write = function(self, data)
		if #self.free < #data then
			local rc = self:flush_write()
			if rc <= 0 then
				return rc
			end
		end
		assert(#data <= #self.free)
		local written	= self.free:save()
		local n		= #data
		copy(self.free.front, data, n)
		self.adjust_free_avail(n)
		written.back = written.front + n
		return written
	end,

	writef = function(self, ...)
		local n		= C.snprintf(nil, 0, ...)
		if #self.free < n then
			self:flush_write()
		end
		assert(n <= #self.free)
		local written	= self.free:save()
		C.snprintf(written.front, #written, ...)
		self.avail.back	= self.avail.back + n
		written.back	= written.front + n
		self.free:pop_front(n)
		return written
	end,
})

return buffer
