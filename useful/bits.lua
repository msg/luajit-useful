--
-- b i t s . l u a
--
local bits = { }

local bit		= require('bit')
local  band		=  bit.band
local  bnot		=  bit.bnot
local  bor		=  bit.bor
local  bswap		=  bit.bswap
local  lshift		=  bit.lshift
local  rshift		=  bit.rshift
local  tobit		=  bit.tobit

function bits.getbits(x, p, n)
	return band(rshift(x, p), bnot(lshift(bnot(0ULL), n)))
end

function bits.setbits(x, p, n, y)
	local m = bnot(lshift(bnot(0ULL), n))
	return bor(band(x, bnot(lshift(m, p))), lshift(band(m, y), p))
end

function bits.swap16(value)
	return rshift(bswap(tobit(value)), 16)
end

function bits.swap32(value)
	return bswap(tobit(value))
end

function bits.swap64(value)
	return bswap(value)
end

return bits
