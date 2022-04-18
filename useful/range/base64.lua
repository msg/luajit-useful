#!/usr/bin/env luajit
--
-- u s e f u l / r a n g e / b a s e 6 4 . l u a
--

local base64	= { }

local ffi	= require('ffi')
local  copy	=  ffi.copy
local  sizeof	=  ffi.sizeof

local bit	= require('bit')
local  band	=  bit.band
local  bor	=  bit.bor
local  lshift	=  bit.lshift
local  rshift	=  bit.rshift

local range	= require('useful.range')
local  uint8	=  range.uint8
local strings	= require('useful.strings')
local  hexdump	=  strings.hexdump

--                      1         2         3         4         5        6
--            0123456789012345678901234567890123456789012345678901234567801234
local b64s = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
local b64e_8	= uint8.vla(64)
copy(b64e_8, b64s, #b64s)
local UNUSED	= 0x80
local PAD	= string.byte('=')
local b64d_8	= uint8.vla(256)
for i=0,255 do
	b64d_8[i] = UNUSED
end
for i=0,sizeof(b64e_8)-1 do
	b64d_8[b64e_8[i]] = i
end
b64d_8[PAD] = 0 -- padding should just be zero

-- aaaaaa aabbbb bbbbcc cccccc

base64.encode_length = function(from_length)
	return 4 * math.floor((from_length + 2) / 3)
end

base64.decode_length = function(from_length)
	return 3 * math.floor((from_length + 3) / 4)
end

base64.encode = function(i8, o8)
	local function encode_chunk(i, o)
		o[0] = b64e_8[                                 rshift(i[0], 2) ]
		o[1] = b64e_8[bor(lshift(band(i[0], 0x03), 4), rshift(i[1], 4))]
		o[2] = b64e_8[bor(lshift(band(i[1], 0x0f), 2), rshift(i[2], 6))]
		o[3] = b64e_8[           band(i[2], 0x3f)                      ]
	end

	local so8 = o8:save()
	if #i8 % 3 > 0 then i8.back[0] = 0 end
	if #i8 % 3 > 1 then i8.back[1] = 0 end
	while #i8 > 2 do
		encode_chunk(i8.front, o8.front)
		i8:pop_front(3)
		o8:pop_front(4)
	end
	if     #i8 == 1 then
		encode_chunk(i8.front, o8.front)
		o8:pop_front(2)
		o8:write_front(PAD)
		o8:write_front(PAD)
	elseif #i8 == 2 then
		encode_chunk(i8.front, o8.front)
		o8:pop_front(3)
		o8:write_front(PAD)
	end
	so8.back = o8.front
	return so8
end

-- aaaaaabb bbbbcccc ccdddddd

base64.decode = function(i8, o8)
	local function decode_chunk(i, o)
		local a, b, c, d = i[0], i[1], i[2], i[3]
		o[0] = bor(lshift(     b64d_8[a],      2),rshift(b64d_8[b],4))
		o[1] = bor(lshift(band(b64d_8[b],0xf), 4),rshift(b64d_8[c],2))
		o[2] = bor(lshift(band(b64d_8[c],0x3), 6),       b64d_8[d]   )
	end
	local so8 = o8:save()
	local pad = 0
	do
		local si8 = i8:save()
		while #si8 > 0 and si8:read_back() == PAD do
			pad = pad - 1
		end
	end
	while #i8 > 3 do
		decode_chunk(i8.front, o8.front)
		i8:pop_front(4)
		o8:pop_front(3)
	end
	so8.back = o8.front + pad
	return so8
end

local function pencode64(s)
	return io.popen('echo -n "'..s..'"|base64'):read()
end

local function pdecode64(s)
	return io.popen('echo -n "'..s..'"|base64 -d'):read()
end

local function printf(...)
	return io.stdout:write(string.format(...))
end

local function test_one(s)
	local failures = 0
	local vi8,i8 = uint8.vla(1024)
	local vo8,o8 = uint8.vla(1024)
	copy(vi8, s)
	i8.back = i8.front + #s
	local r8 = base64.encode(i8,o8)
	local act = r8:to_string()
	local exp = pencode64(s)
	if act ~= exp then
		print(hexdump(act))
		print(hexdump(exp))
		printf("e %5s <%s> <%s> <%s>\n", act==exp, s, act, exp)
		failures = failures + 1
	end
	local s2 = act
	copy(vi8, s2)
	i8 = uint8.from_vla(vi8)
	i8.back = i8.front + #s2
	r8 = base64.decode(i8,uint8.from_vla(vo8))
	act = r8:to_string()
	exp = pdecode64(s2)
	if act ~= exp then
		print(hexdump(act))
		print(hexdump(exp))
		printf("d %5s <%s> <%s> <%s>\n\n", act == exp, s2, act, exp)
		failures = failures + 1
	end
	return failures
end

local function test()
	local s = "The quick brown fox" -- jumps over the lazy dog"
	local failures = 0
	for i=1,#s do
		failures = failures + test_one(s:sub(1,i))
	end
	if failures > 0 then
		print('Failures:', failures)
	end
end

if arg[1] ~= nil then
	test()
end
return base64
