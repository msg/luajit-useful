--
-- u s e f u l / r a n g e / m s g p a c k . l u a
--

--[[lit-meta
name		= "msgpack"
version		= "0.1.0"
description	= "A ffi luajit implementation of the msgpack format."
homepage	= "https://github.com/creationix/msgpack-lua"
keywords	= {"codec", "msgpack"}
license		= "MIT"
]]
local msgpack	= { }

local  floor	=  math.floor
local  huge	=  math.huge

local ffi	= require('ffi')
local  cast	=  ffi.cast
local  fstring	=  ffi.string
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof
local bit	= require('bit')
local  band	=  bit.band
local  bor	=  bit.bor
local  bswap	=  bit.bswap
local  rshift	=  bit.rshift
local  tobit	=  bit.tobit
local bigendian	= ffi.abi('be')

local range	= require('useful.range')
local  uint8	=  range.uint8
local  uint16	=  range.uint16
local  uint32	=  range.uint32
local  uint64	=  range.uint64

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

local POSFIXINT		= 0x00; msgpack.POSFIXINT	= POSFIXINT
local MAXPOSFIXINT	= 0x7f; msgpack.MAXPOSFIXINT	= MAXPOSFIXINT
local FIXMAP		= 0x80; msgpack.FIXMAP		= FIXMAP
local FIXARRAY		= 0x90; msgpack.FIXARRAY	= FIXARRAY
local FIXSTR		= 0xa0; msgpack.FIXSTR		= FIXSTR
local NIL		= 0xc0; msgpack.NIL		= NIL
local NEVERUSED		= 0xc1; msgpack.NEVERUSED	= NEVERUSED
local FALSE		= 0xc2; msgpack.FALSE		= FALSE
local TRUE		= 0xc3; msgpack.TRUE		= TRUE
local BIN8		= 0xc4; msgpack.BIN8		= BIN8
local BIN16		= 0xc5; msgpack.BIN16		= BIN16
local BIN32		= 0xc6; msgpack.BIN32		= BIN32
local EXT8		= 0xc7; msgpack.EXT8		= EXT8
local EXT16		= 0xc8; msgpack.EXT16		= EXT16
local EXT32		= 0xc9; msgpack.EXT32		= EXT32
local FLOAT32		= 0xca; msgpack.FLOAT32		= FLOAT32
local FLOAT64		= 0xcb; msgpack.FLOAT64		= FLOAT64
local UINT8		= 0xcc; msgpack.UINT8		= UINT8
local UINT16		= 0xcd; msgpack.UINT16		= UINT16
local UINT32		= 0xce; msgpack.UINT32		= UINT32
local UINT64		= 0xcf; msgpack.UINT64		= UINT64
local INT8		= 0xd0; msgpack.INT8		= INT8
local INT16		= 0xd1; msgpack.INT16		= INT16
local INT32		= 0xd2; msgpack.INT32		= INT32
local INT64		= 0xd3; msgpack.INT64		= INT64
local FIXEXT1		= 0xd4; msgpack.FIXEXT1		= FIXEXT1
local FIXEXT2		= 0xd5; msgpack.FIXEXT2		= FIXEXT2
local FIXEXT4		= 0xd6; msgpack.FIXEXT4		= FIXEXT4
local FIXEXT8		= 0xd7; msgpack.FIXEXT8		= FIXEXT8
local FIXEXT16		= 0xd8; msgpack.FIXEXT16	= FIXEXT16
local STR8		= 0xd9; msgpack.STR8		= STR8
local STR16		= 0xda; msgpack.STR16		= STR16
local STR32		= 0xdb; msgpack.STR32		= STR32
local ARRAY16		= 0xdc; msgpack.ARRAY16		= ARRAY16
local ARRAY32		= 0xdd; msgpack.ARRAY32		= ARRAY32
local MAP16		= 0xde; msgpack.MAP16		= MAP16
local MAP32		= 0xdf; msgpack.MAP32		= MAP32
local MINNEGFIXINT	= 0xe0; msgpack.MINNEGFIXINT	= MINNEGFIXINT
local MAXNEGFIXINT	= 0xff; msgpack.MAXNEGFIXINT	= MAXNEGFIXINT

local function encode_8(code, value, r8)
	r8:write_front(code)
	r8:write_front(value)
end

local function encode_16(code, value, r8)
	r8:write_front(code)
	local u16 = r8:cast(uint16)
	u16:write_front(fix_endian_16(value))
	r8:set(u16)
end

local function encode_32(code, value, r8)
	r8:write_front(code)
	local u32 = r8:cast(uint32)
	u32:write_front(fix_endian_32(value))
	r8:set(u32)
end

local function encode_64(code, value, r8)
	r8:write_front(code)
	local u64 = r8:cast(uint64)
	u64:write_front(fix_endian_64(value))
	r8:set(u64)
end

local function encode_integer(value, r8)
	-- Encode as smallest integer type that fits
	if value >= 0 then
		if     value < 0x80 then
			r8:write_front(value)
		elseif value < 0x100 then
			encode_8(UINT8, value, r8)
		elseif value < 0x10000 then
			encode_16(UINT16, value, r8)
		elseif value < 0x100000000 then
			encode_32(UINT32, value, r8)
		else
			encode_64(UINT64, value, r8)
		end
	else
		if     value >= -0x20 then
			r8:write_front(0x100 + value)
		elseif value >= -0x80 then
			encode_8(INT8, 0x100 + value, r8)
		elseif value >= -0x8000 then
			encode_16(INT16, 0x10000 + value, r8)
		elseif value >= -0x80000000 then
			encode_32(INT32, 0x100000000 + value, r8)
		--elseif value >= -0x100000000 then
		--	encode_64(0xd3, value, r8)
		else
			encode_64(INT64, value, r8)
		end
	end
end

local function encode_number(value, r8)
	if value == huge or value == -huge or value ~= value then
		-- Encode Infinity, -Infinity and NaN as floats
		value = new('float[1]', value)
		encode_32(FLOAT32, cast('int32_t *', value)[0], r8)
	elseif floor(value) ~= value then
		-- Encode other non-ints as doubles
		value = new('double[1]', value)
		encode_64(FLOAT64, cast('int64_t *', value)[0], r8)
	else
		encode_integer(value, r8)
	end
end

local function encode_string(value, r8)
	local size = #value
	if     size < 0x20 then
		r8:write_front(bor(FIXSTR, size))
	elseif size < 0x100 then
		encode_8(STR8, size, r8)
	elseif size < 0x10000 then
		encode_16(STR16, size, r8)
	elseif size < 0x100000000 then
		encode_32(STR32, size, r8)
	else
		error("String too long: " .. size .. " bytes")
	end
	value = cast('int8_t *', value)
	r8:write_front_range(uint8.meta(value, value + size))
end

local function encode_cdata(value, r8)
	local size = sizeof(value)
	value = fstring(value, size)
	if     size < 0x100 then
		encode_8(BIN8, size, r8)
	elseif size < 0x10000 then
		encode_16(BIN16, size, r8)
	elseif size < 0x100000000 then
		encode_32(BIN32, size, r8)
	else
		error("Buffer too long: " .. size .. " bytes")
	end
	value = cast('int8_t *', value)
	r8:write_front_range(uint8.meta(value, value + size))
end

local encode

local function encode_map(value, size, r8)
	if     size < 0x10 then
		r8:write_front(bor(FIXMAP, size))
	elseif size < 0x10000 then
		encode_16(MAP16, r8, size)
	elseif size < 0x100000000 then
		encode_32(MAP32, r8, size)
	else
		error("map too big: " .. size)
	end
	for key, part in pairs(value) do
		encode(key, r8)
		encode(part, r8)
	end
end

local function encode_array(value, size, r8)
	if     size < 0x10 then
		r8:write_front(bor(FIXARRAY, size))
	elseif size < 0x10000 then
		encode_16(ARRAY16, size, r8)
	elseif size < 0x100000000 then
		encode_32(ARRAY32, size, r8)
	else
		error("Array too long: " .. size .. "items")
	end
	for i = 1,size do
		encode(value[i], r8)
	end
end

local function table_size(value)
	local size = 0
	for _,_ in pairs(value) do
		size = size + 1
	end
	return size
end

local function encode_table(value, r8)
	local size = table_size(value)
	assert(size >= #value)
	if size ~= value then
		encode_map(value, size, r8)
	else
		encode_array(value, size, r8)
	end
end

local encoders = {
	['nil']		= function(value, r8)		--luacheck:ignore
		r8:write_front(NIL)
	end,
	['boolean']	= function(value, r8)
		r8:write_front(value and TRUE or FALSE)
	end,
	number		= encode_number,
	string		= encode_string,
	cdata		= encode_cdata,
	table		= encode_table,
}

encode = function(value, r8)
	local t = type(value)
	local encoder = encoders[t]
	if encoder ~= nil then
		encoder(value, r8)
	else
		error("Unknown type: " .. t)
	end
end

local function decode_8(r8)
	return r8:read_front()
end

local function decode_16(r8)
	local u16 = r8:cast(uint16)
	local value = fix_endian_16(u16:read_front())
	r8:set(u16)
	return value
end

local function decode_32(r8)
	local u32 = r8:cast(uint32)
	local value = fix_endian_32(u32:read_front())
	r8:set(u32)
	return value
end

local function decode_64(r8)
	local u64 = r8:cast(uint64)
	local value = fix_endian_64(u64:read_front())
	r8:set(u64)
	return value
end

local decode

local function decode_array(size, r8)
	local items = {}
	for i=1,size do
		items[i] = decode(r8)
	end
	return items
end

local function decode_map(size, r8)
	local map = {}
	for _=1,size do
		local key = decode(r8)
		map[key] = decode(r8)
	end
	return map
end

local function decode_with_size(size, r8)
	return r8:read_front_size(size)
end

local decoders		= { }

for i=0x00,0xff do
	decoders[i]	= function()
		error("TODO: more types: " .. string.format("%02x", i))
	end
end

for i=0,0x7f do
	decoders[i]	= function() return i end
end
for i=0xe0,0xff do
	decoders[i]	= function() return i - 0x100 end
end
for i=FIXMAP,FIXMAP+15 do
	decoders[i]	= function(r8, code)
		return decode_map(band(code, 0x0f), r8)
	end
end
for i=FIXARRAY,FIXARRAY+16 do
	decoders[i]	= function(r8, code)
		return decode_array(band(code, 0x0f), r8)
	end
end
for i=FIXSTR,FIXSTR+31 do
	decoders[i]	= function(r8, code)
		return decode_with_size(band(code, 0x1f), r8):to_string()
	end
end
decoders[NIL]		= function() return nil end
decoders[NEVERUSED]	= function() error('0xc1 never used') end
decoders[FALSE]		= function() return false end
decoders[TRUE]		= function() return true end
decoders[BIN8]		= function(r8)
	return decode_with_size(decode_8(r8), r8)
end
decoders[BIN16]		= function(r8)
	return decode_with_size(decode_16(r8), r8)
end
decoders[BIN32]		= function(r8)
	return decode_with_size(decode_32(r8), r8)
end
decoders[FLOAT32]	= function(r8)
	local p32	= cast('int32_t *', r8.front)
	local x32	= new('int32_t[1]', fix_endian_32(p32[0]))
	local value	= cast('float *', x32)[0]
	r8:pop_front(sizeof('int32_t'))
	return value
end
decoders[FLOAT64]	= function(r8)
	local p64	= cast('int64_t *', r8.front)
	local x64	= new('int64_t[1]', fix_endian_64(p64[0]))
	local value	= cast('double *', x64)[0]
	r8:pop_front(sizeof('int64_t'))
	return value
end
decoders[UINT8]		= function(r8) return decode_8(r8) end
decoders[UINT16]	= function(r8) return decode_16(r8) end
decoders[UINT32]	= function(r8) return decode_32(r8) end
decoders[UINT64]	= function(r8) return decode_64(r8) end
decoders[INT8]		= function(r8)
	local value	= decode_8(r8)
	return value >= 0x80 and (value - 0x100) or value
end
decoders[INT16]		= function(r8)
	local value	= decode_16(r8)
	return (value >= 0x8000 and (value - 0x10000) or value)
end
decoders[INT32]		= decoders[0xce]
decoders[INT64]		= decoders[0xcf]
decoders[STR8]		= function(r8)
	return decode_with_size(decode_8(r8), r8):to_string()
end
decoders[STR16]		= function(r8)
	return decode_with_size(decode_16(r8), r8):to_string()
end
decoders[STR32]		= function(r8)
	return decode_with_size(decode_32(r8), r8):to_string()
end
decoders[ARRAY16]	= function(r8)
	return decode_array(decode_16(r8), r8)
end
decoders[ARRAY32]	= function(r8)
	return decode_array(decode_32(r8), r8)
end
decoders[MAP16]		= function(r8)
	return decode_map(decode_16(r8), r8)
end
decoders[MAP32]		= function(r8)
	return decode_map(decode_32(r8), r8)
end
-- ext (0xd4~0xd8) type [1,2,4,8,16 byte] data
-- ext (0xc7~0xc9) x type [(1<<x)-1 bytes]  x=8,16,32
-- ext timestamp type=-1
--     0xd6, -1, seconds 32-bit since 1970-01-01
--     0xd7, -1, 30-bit nano-seconds, 34-bit seconds
--     0xd8, -1, 32-bit nano-seconds, 64-bit seconds

decode = function(r8)
	local code = decode_8(r8)
	return decoders[code](r8, code)
end

msgpack.encode = function(data, r8)
	encode(data, r8)
end

msgpack.decode = function (data)
	if type(data) == 'string' then
		data = uint8.from_string(data)
	end
	return decode(data)
end

return msgpack
