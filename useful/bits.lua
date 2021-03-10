#!/usr/bin/lua
--
-- b i t s . l u a
--
local bits = { }

local bit	= require('bit')
local  bor	=  bit.bor
local  bnot	=  bit.bnot
local  band	=  bit.band
local  lshift	=  bit.lshift
local  rshift	=  bit.rshift

function bits.getbits(x, p, n)
	return band(rshift(x, p), bnot(lshift(bnot(0LL), n)))
end

function bits.setbits(x, p, n, y)
	local m = bnot(lshift(bnot(0LL), n))
	return bor(band(x, bnot(lshift(m, p))), lshift(band(m, y), p))
end

return bits
