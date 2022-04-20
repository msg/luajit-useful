#!/usr/bin/env luajit
--
-- u s e f u l / r a n g e / s h a 1 . l u a
--

local sha1	= { }

local ffi	= require('ffi')
local  cast	=  ffi.cast

local bit	= require('bit')
local  band	=  bit.band
local  bnot	=  bit.bnot
local  bor	=  bit.bor
local  bswap	=  bit.bswap
local  bxor	=  bit.bxor
local  lshift	=  bit.lshift
local  rol	=  bit.rol
local  rshift	=  bit.rshift
local  tohex	=  bit.tohex

local range	= require('useful.range')
local  uint8	=  range.uint8
local  uint32	=  range.uint32
local  uint64	=  range.uint64

sha1.sha1_length = function(from_length)
	return lshift(rshift(from_length + 8 + 1 + 0x3f, 6), 6)
end

-- m8:  must be 64 byte aligned
-- len: must < #m8 - 8
sha1.sha1 = function(m8, len)
	local h = uint32.vla(5, {
		0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0,
	})

	-- append "1" bit
	local r8 = m8:save()
	r8:pop_front(len)
	r8:write_front(0x80)

	-- pad to multiple of 64 minus 64bits minus 1 from added 0x80
	local padding_len = band(64 - band(len + 8 + 1, 0x3f), 0x3f)
	for _=0,padding_len-1 do
		r8:write_front(0)
	end

	-- append 64bit length
	local bit_len	= len * 8LL
	local r64	= r8:cast(uint64)
	r64:write_front(bswap(bit_len))
	r8		= m8:save()
	r8.back		= cast('uint8_t *', r64.front)
	local r32	= r8:cast(uint32)
	local words	= uint32.vla(80)
	while #r32 > 0 do
		for j = 0, 15 do
			words[j] = bswap(r32:read_front())
		end
		for j = 16, 79 do
			local xor = bxor(words[j-3], words[j-8],
					words[j-14], words[j-16])
			words[j] = rol(xor, 1)
		end

		local a = h[0]
		local b = h[1]
		local c = h[2]
		local d = h[3]
		local e = h[4]

		local function round(j, f, k)
			local temp = rol(a, 5) + f + e + k + words[j]
			e = d
			d = c
			c = rol(b, 30)
			b = a
			a = temp
		end

		for j = 0, 19 do
			local f = bor(band(b, c), band(bnot(b), d))
			local k = 0x5a827999
			round(j, f, k)
		end
		for j = 20, 39 do
			local f = bxor(b, c, d)
			local k = 0x6ed9eba1
			round(j, f, k)
		end
		for j = 40, 59 do
			local f = bor(band(b, c), band(b, d), band(c, d))
			local k = 0x8f1bbcdc
			round(j, f, k)
		end
		for j = 60, 79 do
			local f = bxor(b, c, d)
			local k = 0xca62c1d6
			round(j, f, k)
		end

		h[0] = h[0] + a
		h[1] = h[1] + b
		h[2] = h[2] + c
		h[3] = h[3] + d
		h[4] = h[4] + e
	end
	for i=0,4 do
		h[i] = bswap(h[i])
	end

	return h, uint32.from_vla(h)
end

local function test()
	local function hex_sha1(s)
		local v8 = uint8.vla(1024, s)
		local m8 = uint8.from_vla(v8)
		local h = sha1(m8, #s)
		s = ''
		for i=0,4 do s = s .. tohex(h[i]) end
		return s
	end

	local function test_sha1(s, e)
		local a = hex_sha1(s)
		print(a)
		print(e)
		print('"'..s..'"', e == a, '\n')
	end

	local e, s
	e = "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12"
	s = "The quick brown fox jumps over the lazy dog"
	test_sha1(s, e)

	e = "de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3"
	s = "The quick brown fox jumps over the lazy cog"
	test_sha1(s, e)

	e = "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	s = ""
	test_sha1(s, e)

	s = "x3JJHMbDL1EzLkh9GBhXDw==" ..
		"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	print(hex_sha1(s))
end

if arg[1] ~= nil then
	test()
end
return sha1
