--
-- b i t s . l u a
--
local bits = { }

local ffi	= require('ffi')
local  cast	=  ffi.cast
local  sizeof	=  ffi.sizeof

local bit	= require('bit')
local  band	=  bit.band
local  bnot	=  bit.bnot
local  bor	=  bit.bor
local  bswap	=  bit.bswap
local  lshift	=  bit.lshift
local  rshift	=  bit.rshift

function bits.getbits(x, p, n)
	return band(rshift(x, p), bnot(lshift(bnot(0LL), n)))
end

function bits.setbits(x, p, n, y)
	local m = bnot(lshift(bnot(0LL), n))
	return bor(band(x, bnot(lshift(m, p))), lshift(band(m, y), p))
end

ffi.cdef [[
typedef union bits_swap_t {
	uint16_t u16[4];
	uint32_t u32[2];
	uint64_t u64[1];
} bits_swap_t;
]]
local bits_swap = ffi.new('bits_swap_t')

function bits.swap16(value)
	bits_swap.u16[3] = value
	return bswap(bits_swap.u64[0])
end

function bits.swap32(value)
	bits_swap.u32[1] = value
	return bswap(bits_swap.u64[0])
end

function bits.swap64(value)
	return bswap(value)
end

function bits.swap(value)
	local size = sizeof(value)
	value = cast('int64_t', value)
	return rshift(bswap(value), 64 - size * 8)
end

return bits
