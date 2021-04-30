#!/usr/bin/lua
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

function bits.swap(value)
	local size = sizeof(value)
	value = cast('int64_t', value)
	return rshift(bswap(value), 64 - size * 8)
end

return bits
