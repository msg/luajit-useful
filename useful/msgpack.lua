--[[lit-meta
name = "creationix/msgpack"
version = "2.3.0"
description = "A pure lua implementation of the msgpack format."
homepage = "https://github.com/creationix/msgpack-lua"
keywords = {"codec", "msgpack"}
license = "MIT"
comments = 'updated and cleaned up by me"
]]

local  floor	=  math.floor
local  huge	=  math.huge
local  char	=  string.char
local  byte	=  string.byte
local  sub	=  string.sub
local  concat	=  table.concat
local  insert	=  table.insert
local bit	= require('bit')
local  band	=  bit.band
local  bor	=  bit.bor
local  bswap	=  bit.bswap
local  rshift	=  bit.rshift
local  tobit	=  bit.tobit
local ffi	= require('ffi')
local  cast	=  ffi.cast
local  copy	=  ffi.copy
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof
local  typeof	=  ffi.typeof
local bigendian	= ffi.abi('be')

ffi.cdef [[
typedef union {
	uint8_t		b[8];
	double		d;
	float 		f;
	int8_t		i8;
	int16_t		i16;
	int32_t		i32;
	int64_t		i64;
} msgpack_union_t;
]]

local union	= new('msgpack_union_t')
local i16size	= sizeof('int16_t')
local i32size	= sizeof('int32_t')
local i64size	= sizeof('int64_t')

local buffer	= typeof('uint8_t[?]')

local fix_endian_64, fix_endian_32, fix_endian_16

if bigendian then
	fix_endian_64 = function(x) -- ignore size
		return x
	end
	fix_endian_32 = fix_endian_64
	fix_endian_16 = fix_endian_32
else
	fix_endian_64 = function(x)
		return bswap(x)
	end
	fix_endian_32 = function(x)
		return bswap(tobit(x))
	end
	fix_endian_16 = function(x)
		return rshift(bswap(tobit(x)), 16)
	end
end

local encode8 = char

local function encode16(num)
	union.i16 = fix_endian_16(num)
	return ffi.string(union.b, i16size)
end

local function encode32(num)
	union.i32 = fix_endian_32(num)
	return ffi.string(union.b, i32size)
end

local function encode64(num)
	union.i64 = fix_endian_64(new('int64_t', num))
	return ffi.string(union.b, i64size)
end

local decode8 = byte

local function decode16(data, offset)
	local p = cast('char *', data)
	copy(union.b, p + offset - 1, i16size)
	return fix_endian_16(union.i16)
end

local function decode32(data, offset)
	local p = cast('char *', data)
	copy(union.b, p + offset - 1, i32size)
	return fix_endian_32(union.i32)
end

local function decode64(data, offset)
	local p = cast('char *', data)
	copy(union.b, p + offset - 1, i64size)
	return fix_endian_64(union.i64)
end

local function encode_integer(value)
	-- Encode as smallest integer type that fits
	if value >= 0 then
		if value < 0x80 then
			return encode8(value)
		elseif value < 0x100 then
			return encode8(0xcc, value)
		elseif value < 0x10000 then
			return encode8(0xcd) .. encode16(value)
		elseif value < 0x100000000 then
			return encode8(0xce) .. encode32(value)
		else
			return encode8(0xcf) .. encode64(value)
		end
	else
		if value >= -0x20 then
			return encode8(0x100 + value)
		elseif value >= -0x80 then
			return encode8(0xd0, 0x100 + value)
		elseif value >= -0x8000 then
			return encode8(0xd1) .. encode16(0x10000 + value)
		elseif value >= -0x80000000 then
			return encode8(0xd2) .. encode32(0x100000000 + value)
		elseif value >= -0x100000000 then
			return encode8(0xd3, 0xff, 0xff, 0xff, 0xff)
			.. encode32(0x100000000 + value)
		else
			return encode8(0xd3) .. encode64(value)
		end
	end
end

local function encode_number(value)
	if value == huge or value == -huge or value ~= value then
		-- Encode Infinity, -Infinity and NaN as floats
		union.f = value
		union.i32 = fix_endian_32(union.i32)
		return encode8(0xca) .. ffi.string(union.b, 4)
	elseif floor(value) ~= value then
		-- Encode other non-ints as doubles
		union.d = value
		union.i64 = fix_endian_64(union.i64)
		return encode8(0xcb) .. ffi.string(union.b, 8)
	else
		return encode_integer(value)
	end
end

local function encode_string(value)
	local l = #value
	if l < 0x20 then
		return encode8(bor(0xa0, l)) .. value
	elseif l < 0x100 then
		return encode8(0xd9) .. encode8(l) .. value
	elseif l < 0x10000 then
		return encode8(0xda) .. encode16(l) .. value
	elseif l < 0x100000000 then
		return encode8(0xdb) .. encode32(l) .. value
	else
		error("String too long: " .. l .. " bytes")
	end
end

local function encode_cdata(value)
	local l = sizeof(value)
	value = ffi.string(value, l)
	if l < 0x100 then
		return encode8(0xc4) .. encode8(l) .. value
	elseif l < 0x10000 then
		return encode8(0xc5) .. encode16(l) .. value
	elseif l < 0x100000000 then
		return encode8(0xc6) .. encode32(l) .. value
	else
		error("Buffer too long: " .. l .. " bytes")
	end
end

local encode

local function encode_table(value)
	local is_map = false
	local index = #value
	if index == 0 then
		index = nil
	end
	if next(value, index) then
		is_map = true
	end
	if is_map == true then
		local parts = {}
		local count = 0
		for key, part in pairs(value) do
			insert(parts, encode(key))
			insert(parts, encode(part))
			count = count + 1
		end
		value = concat(parts)
		if count < 0x10 then
			return encode8(bor(0x80, count)) .. value
		elseif count < 0x10000 then
			return encode8(0xde) .. encode16(count) .. value
		elseif count < 0x100000000 then
			return encode8(0xdf) .. encode32(count) .. value
		else
			error("map too big: " .. count)
		end
	else
		local parts = {}
		local l = index
		for i = 1, l do
			insert(parts, encode(value[i]))
		end
		value = concat(parts)
		if l < 0x10 then
			return encode8(bor(0x90, l)) .. value
		elseif l < 0x10000 then
			return encode8(0xdc) .. encode16(l) .. value
		elseif l < 0x100000000 then
			return encode8(0xdd) .. encode32(l) .. value
		else
			error("Array too long: " .. l .. "items")
		end
	end
end

local encoders = {
	['nil']		= function() return encode8(0xc0) end,
	boolean		= function(value)
		return value and encode8(0xc3) or encode8(0xc2)
	end,
	number		= encode_number,
	string		= encode_string,
	cdata		= encode_cdata,
	table		= encode_table,
}

encode = function(value)
	local t = type(value)
	local encoder = encoders[t]
	if encoder ~= nil then
		return encoder(value)
	else
		error("Unknown type: " .. t)
	end
end

local decode

local function decode_array(count, data, offset, start)
	local items = {}
	for i = 1, count do
		local len
		items[i], len = decode(data, start)
		start = start + len
	end
	return items, start - offset
end

local function decode_map(count, data, offset, start)
	local map = {}
	for _ = 1, count do
		local len, key
		key, len = decode(data, start)
		start = start + len
		map[key], len = decode(data, start)
		start = start + len
	end
	return map, start - offset
end

decode = function(data, offset)
	local c = decode8(data, offset + 1)
	if c < 0x80 then
		return c, 1
	elseif c >= 0xe0 then
		return c - 0x100, 1
	elseif c < 0x90 then
		return decode_map(band(c, 0x0f), data, offset, offset + 1)
	elseif c < 0xa0 then
		return decode_array(band(c, 0x0f), data, offset, offset + 1)
	elseif c < 0xc0 then
		local len = 1 + band(c, 0x1f)
		return sub(data, offset + 2, offset + len), len
	elseif c == 0xc0 then
		return nil, 1
	elseif c == 0xc2 then
		return false, 1
	elseif c == 0xc3 then
		return true, 1
	elseif c == 0xcc then
		return decode8(data, offset + 2), 2
	elseif c == 0xcd then
		return decode16(data, offset + 2), 3
	elseif c == 0xce then
		return decode32(data, offset + 2), 5
	elseif c == 0xcf then
		return decode64(data, offset + 2), 9
	elseif c == 0xd0 then
		local num = decode8(data, offset + 2)
		return (num >= 0x80 and (num - 0x100) or num), 2
	elseif c == 0xd1 then
		local num = decode16(data, offset + 2)
		return (num >= 0x8000 and (num - 0x10000) or num), 3
	elseif c == 0xd2 then
		return decode32(data, offset + 2), 5
	elseif c == 0xd3 then
		return decode64(data, offset + 2), 9
	elseif c == 0xd9 then
		local len = 2 + decode8(data, offset + 2)
		return sub(data, offset + 3, offset + len), len
	elseif c == 0xda then
		local len = 3 + decode16(data, offset + 2)
		return sub(data, offset + 4, offset + len), len
	elseif c == 0xdb then
		local len = 5 + decode32(data, offset + 2)
		return sub(data, offset + 6, offset + len), len
	elseif c == 0xc4 then
		local bytes = decode8(data, offset + 2)
		local len = 2 + bytes
		return buffer(bytes, sub(data, offset + 3, offset + len)), len
	elseif c == 0xc5 then
		local bytes = decode16(data, offset + 2)
		local len = 3 + bytes
		return buffer(bytes, sub(data, offset + 4, offset + len)), len
	elseif c == 0xc6 then
		local bytes = decode32(data, offset + 2)
		local len = 5 + bytes
		return buffer(bytes, sub(data, offset + 6, offset + len)), len
	elseif c == 0xca then
		local p = cast('char *', data)
		copy(union.b, p + 2, 4)
		union.i32 = fix_endian_32(union.i32, i32size)
		return union.f, 5
	elseif c == 0xcb then
		local p = cast('char *', data)
		copy(union.b, p + 2, 8)
		union.i64 = fix_endian_32(union.i64, i64size)
		return union.d, 9
	elseif c == 0xdc then
		local len = decode16(data, offset + 2)
		return decode_array(len, data, offset, offset + 3)
	elseif c == 0xdd then
		local len = decode32(data, offset + 2)
		return decode_array(len, data, offset, offset + 5)
	elseif c == 0xde then
		local len = decode16(data, offset + 2)
		return decode_map(len, data, offset, offset + 3)
	elseif c == 0xdf then
		local len = decode32(data, offset + 2)
		return decode_map(len, data, offset, offset + 5)
	else
		error("TODO: more types: " .. string.format("%02x", c))
	end
end

local msgpack = { }

msgpack.encode = encode

msgpack.decode = function (data, offset)
	return decode(data, offset or 0)
end

return msgpack
