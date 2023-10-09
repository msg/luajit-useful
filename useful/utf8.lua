#!/usr/bin/luajit

local utf8 = { }

local  byte		=  string.byte

local  unpack		=  unpack or table.unpack -- luacheck:ignore

-- luacheck: push ignore
local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  copy		=  ffi.copy
local  errno		=  ffi.errno
local  fstring		=  ffi.string
local  gc		=  ffi.gc
local  metatype		=  ffi.metatype
local  new		=  ffi.new
local  offset		=  ffi.offset
local  sizeof		=  ffi.sizeof
local  typeof		=  ffi.typeof
-- luacheck: pop
-- luacheck: push ignore
local bit		= require('bit')
local  arshift		=  bit.arshift
local  band		=  bit.band
local  bnot		=  bit.bnot
local  bor		=  bit.bor
local  bswap		=  bit.bswap
local  bxor		=  bit.bxor
local  lshift		=  bit.lshift
local  rol		=  bit.rol
local  ror		=  bit.ror
local  rshift		=  bit.rshift
local  tobit		=  bit.tobit
local  tohex		=  bit.tohex
-- luacheck: pop

local lengths = new('char[256]', {
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
	2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,
	3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,5,5,5,5,6,6,1,1,
})
utf8.lengths		= lengths

local masks		= new('char[6]', 0x7f, 0x1f, 0x0f, 0x07, 0x03, 0x01)
utf8.masks		= masks

local function utf8_to_unicode(s)
	local l		= #s
	s		= cast('uint8_t *', s)
	local len	= lengths[s[0]]
	if s[0] == 0 or l < len then
		return
	end
	local code	= band(s[0], masks[len-1])
	for i=1,len-1 do
		code = bor(lshift(code, 6), band(s[i], 0x3f))
	end
	return code, len
end
utf8.utf8_to_unicode = utf8_to_unicode

local function unicode_to_utf8(code)
	local len, first
	if     code < 0x80 then		first	= 0x00	len	= 1
	elseif code < 0x800 then	first	= 0xc0	len	= 2
	elseif code < 0x10000 then	first	= 0xe0	len	= 3
	elseif code < 0x200000 then	first	= 0xf0	len	= 4
	elseif code < 0x4000000 then	first	= 0xf8	len	= 5
	else				first	= 0xfc	len	= 6
	end
	local s = new('uint8_t[?]', len)
	for i=len-1,1,-1 do
		s[i]	= bor(band(code, 0x3f), 0x80)
		code	= rshift(code, 6)
	end
	s[0]		= bor(code, first)
	return fstring(s, len)
end
utf8.unicode_to_utf8 = unicode_to_utf8

utf8.charpattern = '[\0-\x7f\xc2-\xf4][\x80-\xbf]*'

function utf8.char(...)
	local strs = { }
	for _,code in pairs({...}) do
		table.insert(strs, unicode_to_utf8(code))
	end
	return table.concat(strs)
end

function utf8.codes(s)
	local pos = 1
	return function()
		local c, len	= utf8_to_unicode(s:sub(pos))
		if not c then return end
		local p		= pos
		pos		= pos + len
		return p, c
	end
end

local position = function(pos, len)
	if pos >= 0 then
		return pos
	elseif 0 - pos > len then
		return 1
	else
		return len + pos + 1
	end
end

function utf8.codepoint(s, i, j)
	i = position(i or 1, #s) assert(i >= 1, 'out of range')
	j = position(j or i, #s) assert(j <= #s, 'out of range')
	local n = j - i + 1
	s = s:sub(i)
	local codes = { }
	while s ~= '' and n > 0 do
		local code, len = utf8_to_unicode(s)
		if code == nil then
			error('invalid UTF-8 code')
		end
		s = s:sub(len)
		n = n - 1
	end
	return unpack(codes)
end

function utf8.len(s, i, j)
	i = position(i or 1, #s) assert(1 <= i and i <= #s, 'initial position out of string')
	j = position(j or -1, #s) assert(j <= #s, 'final position out of string')
	s = s:sub(i, j)
	local n = 0
	while i < j do
		local code, len = utf8_to_unicode(s:sub(i))
		if code == nil then
			return nil, i
		end
		i = i + len
		n = n + 1
	end
end

function utf8.offset(s, n, i)
	local function iscont(c)
		return band(byte(c), 0xc0) == 0x80
	end
	local j = n >= 0 and 1 or #s + 1
	i = position(i or j, #s)
	assert(1 <= i and i <= #s, 'position out of range')
	if n == 0 then
		while i > 1 and iscont(s:sub(i, i)) do
			i = i - 1
		end
	else
		if iscont(s:sub(i, i)) then
			error('initial position is a continuation byte')
		end
		if n < 0 then
			while n < 0 and i > 1 do
				repeat
					i = i - 1
				until not (i > 1 and iscont(s:sub(i,i)))
				n = n + 1
			end
		else
			n = n - 1
			while n > 0 and i <= #s do
				repeat
					i = i + 1
				until not iscont(s:sub(i,i))
				n = n - 1
			end
		end
	end
	if n == 0 then
		return i
	end
end

function utf8.literal(s)
	return s:gsub('%\\u%(%b{})', function(u)
		return utf8.codes(tonumber(u:sub(2,-2), 16))
	end)
end

return utf8
