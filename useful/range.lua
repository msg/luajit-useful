#!/usr/bin/luajit
--
-- r a n g e . l u a
--
local range = { }

local ffi	= require('ffi')
local  cast	=  ffi.cast
local  copy	=  ffi.copy
local  fstring	=  ffi.string
local  metatype	=  ffi.metatype
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof
local  typeof	=  ffi.typeof
local bit	= require('bit')
local  bswap	=  bit.bswap
local  rshift	=  bit.rshift

local stdio	= require('useful.stdio')
local  printf	=  stdio.printf
local system	= require('useful.system')
local  is_main	=  system.is_main

local range_types = { }

function range.range_type(declaration)
	if range_types[declaration] ~= nil then
		return range_types[declaration]
	end

	local rmt	= { }

	rmt.__index	= rmt
	rmt.rmt		= rmt
	rmt.declaration	= declaration
	rmt.sizeof	= sizeof(declaration)
	rmt.sizemask	= rmt.sizeof - 1
	rmt.pointer	= typeof(rmt.declaration .. '*')
	rmt.struct	= typeof('struct { $ front, back; }', rmt.pointer)
	rmt.meta	= metatype(rmt.struct, rmt)
	rmt.cast	= function(self, type_range)
		return type_range(cast(type_range.pointer, self.front),
				cast(type_range.pointer, self.back))
	end
	rmt.set		= function(self, from)
		self.front = cast(rmt.pointer, from.front)
		self.back = cast(rmt.pointer, from.back)
	end
	rmt.swap	= function(value)
		value = cast('int64_t',value)
		return rshift(bswap(value), 64-rmt.sizeof*8)
	end

	-- input range api
	function rmt.empty(self) return self.front >= self.back end
	function rmt.pop_front(self, n) self.front = self.front + (n or 1) end
	function rmt.get_front(self) return self.front[0] end
	function rmt.set_front(self, v) self.front[0] = v end
	function rmt.read_front(self)
		local e = self:get_front()
		self:pop_front()
		return e
	end
	-- bi-directional range api
	function rmt.pop_back(self, n) self.back = self.back - (n or 1) end
	function rmt.get_back(self) return self.back[-1] end
	function rmt.set_back(self, v) self.back[-1] = v end
	function rmt.read_back(self)
		local e = self:get_back()
		self:pop_back()
		return e
	end
	-- forward range api
	function rmt.save(self) return rmt.meta(self.front, self.back) end
	-- random access range api
	function rmt.size(self) return self.back - self.front end
	rmt.__len = rmt.size
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
		end
		return rmt.meta(self.front + i, self.front + j)
	end
	-- output range api
	function rmt.write_front(self, v)
		self.front[0] = v
		self:pop_front()
	end
	function rmt.write_back(self, v)
		self.back[-1] = v
		self:pop_back()
	end
	-- array manipulation functions
	function rmt.from_vla(array)
		return rmt.meta(array, array + sizeof(array))
	end
	function rmt.vla(size, ...)
		local vla = new(rmt.declaration..'[?]', size, ...)
		return vla,  rmt.from_vla(vla)
	end
	function rmt.to_vla(self)
		local size	= self:size()
		local size1	= sizeof(self.declaration)
		local array	= rmt.vla(size)
		copy(array, self.front, size * size1)
		return array
	end
	function rmt.from_string(s)
		local p = cast('char *', s)
		return rmt.meta(p, p + #s)
	end
	function rmt.to_string(self)
		return fstring(self.front, self:size())
	end

	range_types[declaration] = rmt.meta

	return rmt.meta
end

for _,size in ipairs({'8','16','32','64'}) do
	range['int'..size] = range.range_type('int'..size..'_t')
	range['uint'..size] = range.range_type('uint'..size..'_t')
end
range.char	= range.int8
range.float	= range.range_type('float')
range.double	= range.range_type('double')

local table_mt = { }
function table_mt:empty()	return self.front < self.back		end
function table_mt:pop_front(n)	self.front = self.front + (n or 1)	end
function table_mt:get_front()	return self.table[self.front]		end
function table_mt:read_front()
	local v = self.table[self.front]
	self.front = self.front + 1
	return v
end
function table_mt:write_front(v)
	self.front[0] = v
	self.front = self.front + 1
end
function table_mt:pop_back(n)	self.back = self.back - (n or 1)	end
function table_mt:get_back()	return self.table[self.back - 1]	end
function table_mt:set_back(v)	self.back[-1] = v			end
function table_mt:read_back()
	local v = self.table[self.back - 1]
	self.back = self.back - 1
	return v
end
function table_mt:write_back(v)
	self.table[self.back - 1] = v
	self.back = self.back - 1
end
function table_mt:size()	return self.back - self.front		end
function table_mt:save()
	local table_range = range.table(self.table)
	table_range.front = self.front
	table_range.back = self.back
	return table_range
end
table_mt.__len = table_mt.size
range.table = function(t)
	return setmetatable({
		table	=	t,
		front	=	1,
		back	=	#t + 1,
	}, table_mt)
end

local string_mt = { }
function string_mt:empty()	return self.front < self.back		end
function string_mt:pop_front(n)	self.front = self.front + (n or 1)	end
function string_mt:get_front()
	return self.string:sub(self.front, self.front)
end
function string_mt:set_front(v)
	self.string = v..self.string:sub(2)
end
function string_mt:read_front()
	local v = self:get_front()
	self.front = self.front + 1
	return v
end
function string_mt:write_front(v)
	self.set_front(v)
	self.front = self.front + 1
	return v
end
function string_mt:pop_back(n)	self.back = self.back - (n or 1)	end
function string_mt:get_back()
	return self.string:sub(self.back - 1, self.back - 1)
end
function string_mt:set_back(v)
	self.string = self.string:sub(-1)..v
end
function string_mt:read_back()
	local v = self:get_back()
	self.back = self.back - 1
	return v
end
function string_mt:write_back(v)
	self:set_back(v)
	self.back = self.back - 1
	return v
end
function string_mt:size()	return self.back - self.front		end
string_mt.__len = string_mt.size
function string_mt:save()
	local string_range = range.string(self.string)
	string_range.front = self.front
	string_range.back = self.back
	return string_range
end
range.string = function(s)
	return setmetatable({
		string	=	s,
		front	=	1,
		back	=	#s + 1,
	}, string_mt)
end

local retro_mt = { }
retro_mt.__index = retro_mt
function retro_mt:empty()	return self.range:empty()	end
function retro_mt:pop_front(n)	self.range:pop_back(n)		end
function retro_mt:get_front()	return self.range:get_back()	end
function retro_mt:set_front(v)	self.range:set_back(v)		end
function retro_mt:read_front()	return self.range:read_back()	end
function retro_mt:pop_back(n)	self.range:pop_front(n)		end
function retro_mt:get_back()	return self.range:get_front()	end
function retro_mt:set_back(v)	self.range:set_front(v)		end
function retro_mt:read_back()	return self.range:read_front()	end
function retro_mt:size()	return #self.range		end
retro_mt.__len = retro_mt.size
range.retro = function(range) -- luacheck:ignore
	return setmetatable({ range=range }, retro_mt)
end
function retro_mt:save()	return range.retro(self.range:save()) end

local chain_mt = { }
chain_mt.__index = chain_mt
function chain_mt:skip_empty_fronts()
	while self.front_index < self.back_index and
	      self.ranges[self.front_index]:empty() do
		self.front_index = self.front_index + 1
	end
end
function chain_mt:empty()
	self:skip_empty_fronts()
	return self.ranges[self.front_index]:empty()
end
function chain_mt:pop_front(n)
	self:skip_empty_fronts()
	n = n or 1
	while n > 0 do
		local s = math.min(n, #self.ranges[self.front_index])
		self.ranges[self.front_index]:pop_front(s)
		self.front_index = self.front_index + 1
		n = n - s
	end
end
function chain_mt:get_front()
	self:skip_empty_fronts()
	return self.ranges[self.front_index]:get_front()
end
function chain_mt:set_front(v)
	self:skip_empty_fronts()
	self.ranges[self.front_index]:set_front(v)
end
function chain_mt:read_front()
	self:skip_empty_fronts()
	return self.ranges[self.front_index]:read_front()
end
function chain_mt:write_front(v)
	self:skip_empty_fronts()
	self.ranges[self.front_index]:write_front(v)
end
function chain_mt:size()
	local front	= self.front_index
	local length	= 0
	while front <= self.back_index do
		length = length + #self.ranges[front]
		front = front + 1
	end
	return length
end
chain_mt.__len = chain_mt.size
function chain_mt:skip_empty_backs()
	while self.front_index < self.back_index and
	      self.ranges[self.back_index]:empty() do
		self.back_index = self.back_index - 1
	end
end
function chain_mt:pop_back(n)
	self:skip_empty_backs()
	n = n or 1
	while n > 0 do
		local s = math.min(n, #self.ranges[self.back_index])
		self.ranges[self.back_index]:pop_back(s)
		self.back_index = self.back_index - 1
		n = n - s
	end
end
function chain_mt:get_back()
	self:skip_empty_backs()
	return self.ranges[self.back_index]:get_back()
end
function chain_mt:set_back(v)
	self:skip_empty_backs()
	self.ranges[self.back_index]:set_back(v)
end
function chain_mt:read_back()
	self:skip_empty_backs()
	return self.ranges[self.back_index]:read_back()
end
function chain_mt:write_back(v)
	self:skip_empty_backs()
	return self.ranges[self.back_index]:write_back(v)
end

range.chain = function(...)
	local ranges = {...}
	return setmetatable({
		ranges		= ranges,
		front_index	= 1,
		back_index	= #ranges,
	}, chain_mt)
end

function chain_mt:save()
	local ranges = { }
	for i=self.front_index,self.back_index do
		table.insert(ranges, self.ranges[i]:save())
	end
	return range.chain(unpack(ranges))
end

local take_mt = { }
take_mt.__index = take_mt
function take_mt:empty()
	return self.range:empty() or self.n > 0
end
function take_mt:pop_front()
	n = math.min(self.n, self.range:size())
	self.range:pop_front(n)
	self.n = self.n - n
end
function take_mt:get_front()
	return self.range:get_front()
end
function take_mt:set_front(v)
	self.range:set_front(v)
end
function take_mt:read_front()
	local v = self:get_front()
	self:pop_front()
	return v
end
function take_mt:write_front(v)
	self:set_front(v)
	self:pop_front()
end

range.take = function(range, n) -- luacheck:ignore
	return setmetatable({
		range	= range,
		n	= n,
	}, take_mt)
end

local function main()
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
			printf("swap:read_front(%s))=0x%s\n", r.declaration,
					bit.tohex(r.swap(r:read_front())))
		end
	end
	s = 'testing 1 2 3'
	r8 = range.int8.from_string(s)
	while not r8:empty() do
		printf('%s front=%s\n', r8.declaration,
				string.char(r8:read_front()))
	end
end

if is_main() then
        main()
end

return range

