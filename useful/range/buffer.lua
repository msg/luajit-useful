--
-- b u f f e r . l u a
--
local  min		=  math.min

local ffi		= require('ffi')
local  copy		=  ffi.copy

local class		= require('useful.class')
local  Class 		=  class.Class
local range		= require('useful.range')
local  char		=  range.char
local stdio		= require('useful.stdio')
local  sprintf		=  stdio.sprintf

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
		self.buffer, self.free = char.vla(size)
		self.avail	= char(self.free.front, self.free.front)
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
		if not force and #self.avail ~= 0 then
			return nil, '#avail is not zero. #avail='..
					tostring(#self.avail)
		end
		self.free.front		= self.buffer
		self.avail.front	= self.buffer
		self.avail.back		= self.avail.front
		return 0
	end,

	flush_write = function(self)
		local nbytes = 0
		local avail = self.avail
		local r, err
		while #avail > 0 do			--luacheck:ignore
			r, err = self.write_func(avail.front, #avail)
			if not r then
				break
			end
			nbytes = nbytes + r
			avail:pop_front(r)
		end
		if nbytes > 0 and #avail > 0 then	-- wrote some
			return nbytes
		elseif not r then			-- wrote none
			return r, err
		end
		r, err = self:flush()			-- wrote all
		if not r then
			return r, err, nbytes
		else
			return nbytes
		end
	end,

	read_more = function(self, nbytes)
		nbytes = nbytes or #self.free
		local n, err = self.read_func(self.free.front, nbytes)
		if not n then
			return n, err
		elseif n == 0 then
			return nil, 'timeout'
		end
		self:pop_insert(n)
		return tonumber(n)
	end,

	read_avail = function(self, nbytes)
		nbytes = nbytes or #self.avail
		local r8 = self.avail:front_range(nbytes)
		self.avail:pop_front(#r8)
		return r8
	end,

	read = function(self, nbytes)
		nbytes = min(nbytes, #self.avail + #self.free)
		while #self.avail < nbytes do
			local ok, err = self:read_more(nbytes - #self.avail)
			if not ok then
				return ok, err
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
			local ok, err = self:read_more()
			if not ok then
				return ok, err
			end
		end
		line.back	= line.front + 1
		line.front	= self.avail.front
		self.avail:pop_front(#line)
		return line
	end,

	write = function(self, data)
		if type(data) == 'string' then
			data	= char.from_string(data)
		end
		local nbytes	= min(#data, #self.free)
		local r8	= self.free:front_range(nbytes)
		copy(r8.front, data.front, nbytes)
		self:pop_insert(nbytes)
		return r8
	end,

	writef = function(self, ...)
		local s = sprintf(...)
		if #self.free < #s+1 then
			error('not enough space')
		end
		local r8	= self.free:front_range(#s)
		ffi.copy(r8.front, s, #s)
		self:pop_insert(#s)
		return r8
	end,
})

return buffer
