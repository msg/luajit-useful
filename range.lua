#!/usr/bin/luajit
--
-- r a n g e . l u a
--
local range = { }

local ffi	= require('ffi')
local bit	= require('bit')
local  rshift	=  bit.rshift
local  bswap	=  bit.bswap

local stdio	= require('useful.stdio')
local  printf	=  stdio.printf

local range_types = { }

function range.range_type(declaration)
	if range_types[declaration] ~= nil then
		return range_types[declaration]
	end

	local rmt	= { }

	rmt.__index	= rmt
	rmt.declaration	= declaration
	rmt.sizeof	= ffi.sizeof(declaration)
	rmt.pointer	= ffi.typeof(rmt.declaration .. '*')
	rmt.struct	= ffi.typeof('struct { $ front, back; }', rmt.pointer)
	rmt.meta	= ffi.metatype(rmt.struct, rmt)
	rmt.cast	= function(self, type_range)
		return type_range(ffi.cast(type_range.pointer, self.front),
				ffi.cast(type_range.pointer, self.back))
	end
	rmt.swap	= function(value)
		value = ffi.cast('int64_t',value)
		return rshift(bswap(value), 64-rmt.sizeof*8)
	end

	-- input range api
	function rmt.empty(self) return self.front >= self.back end
	function rmt.pop_front(self, n) self.front = self.front + (n or 1) end
	function rmt.get_front(self) return self.front[0] end
	function rmt.set_front(self, v) self.front[0] = v end
	function rmt.move_front(self)
		local e = self:get_front()
		self:pop_front()
		return e
	end
	function rmt.move_front_swap(self)
		return rmt.swap(self:move_front())
	end
	-- bi-directional range api
	function rmt.pop_back(self, n) self.back = self.back - (n or 1) end
	function rmt.get_back(self) return self.back[-1] end
	function rmt.set_back(self, v) self.back[-1] = v end
	function rmt.move_back(self)
		local e = self:get_back()
		self:pop_back()
		return e
	end
	function rmt.move_back_swap(self)
		return rmt.swap(self:move_back())
	end
	-- forward range api
	function rmt.save(self) return rmt.meta(self.front, self.back) end
	-- random access range api
	function rmt.size(self) return self.back - self.front end
	function rmt.slice(self, i, j)
		if not i then
			i = 0
		elseif i < 0 then
			i = self:size() - i
		end
		if not j then
			j = self:size()
		elseif j < 0 then
			j = self:size() - j
		elseif j > self:size() then
			j = self:size()
		end
		return rmt.meta(self.front + i, self.front + j)
	end
	-- output range api
	function rmt.put_front(self, v)
		self.front[0] = v
		self:pop_front()
	end
	function rmt.put_back(self, v)
		self.back[-1] = v
		self:pop_back()
	end
	function rmt.put_front_swap(self, v)
		self:put_front(rmt.swap(v))
	end
	function rmt.put_back_swap(self, v)
		self:put_back(rmt.swap(v))
	end
	-- array manipulation functions
	function rmt.vla(size, ...)
		return ffi.new(rmt.declaration..'[?]', size, ...)
	end
	function rmt.from_vla(array)
		return rmt.meta(array, array + ffi.sizeof(array))
	end
	function rmt.to_vla(self)
		local size	= self:size()
		local sizeof	= ffi.sizeof(self.declaration)
		local array	= rmt.vla(size)
		ffi.copy(array, self.front, size * sizeof)
		return array
	end
	function rmt.from_string(s)
		local p = ffi.cast('char *', s)
		return rmt.meta(p, p + #s)
	end
	function rmt.to_string(self)
		return ffi.string(self.front, self:size())
	end

	range_types[declaration] = rmt.meta

	return rmt.meta
end

for _,size in ipairs({'8','16','32','64'}) do
	range['int'..size] = range.range_type('int'..size..'_t')
	range['uint'..size] = range.range_type('uint'..size..'_t')
end
range.float  = range.range_type('float')
range.double = range.range_type('double')

local function main()
	local function printf(...)
		io.stdout:write(string.format(...))
	end

	local a = { }
	for i=1,256 do a[i] = i end
	local s = range.int8.vla(256, a)
	--for i=0,255 do s[i] = i end
	local r8 = range.int8.from_vla(s)
	printf("type(r8)=%s\n", type(r8))
	printf("r8:size=%d\n", r8:size())
	local types = { range.int16, range.int32, range.int64 }
	for _,type in ipairs(types) do
		local r = r8:cast(type)
		while not r:empty() do
			printf("move_front_swap(%s)=0x%s\n", r.declaration,
					bit.tohex(r:move_front_swap()))
		end
	end
	s = 'testing 1 2 3'
	r8 = range.int8.from_string(s)
	while not r8:empty() do
		printf('%s front=%s\n', r8.declaration,
				string.char(r8:move_front()))
	end
end

local function is_main(level)
        return debug.getinfo(4 + (level or 0)) == nil
end

if is_main() then
        main()
end

return range

