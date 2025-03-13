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

function bits.getbits64(x, p, n)
	return band(rshift(x+0ULL, p), bnot(lshift(bnot(0ULL), n)))
end

function bits.setbits64(x, p, n, y)
	local m = bnot(lshift(bnot(0ULL), n))
	return bor(band(x+0ULL, bnot(lshift(m, p))), lshift(band(m, y), p))
end

function bits.getbits32(x, p, n)
	return band(rshift(tobit(x), p), bnot(lshift(tobit(bnot(0ULL)), n)))
end
bits.getbits = bits.getbits32

function bits.setbits32(x, p, n, y)
	local m = bnot(lshift(bnot(tobit(0)), n))
	return bor(band(tobit(x), bnot(lshift(m, p))), lshift(band(m, y), p))
end
bits.setbits = bits.setbits32

function bits.swap16(value)
	return rshift(bswap(tobit(value)), 16)
end

function bits.swap32(value)
	return bswap(tobit(value))
end

function bits.swap64(value)
	return bswap(value+0ULL)
end

return bits
