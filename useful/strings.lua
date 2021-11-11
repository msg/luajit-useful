--
-- u s e f u l / s t r i n g s . l u a
--
local strings = { }

local  insert		=  table.insert
local  concat		=  table.concat

local  byte		=  string.byte
local  char		=  string.char
local  rep		=  string.rep
local  sprintf		=  string.format

local bit		= require('bit')
local  bor		=  bit.bor
local  band		=  bit.band
local  lshift		=  bit.lshift
local  rshift		=  bit.rshift

local system		= require('useful.system')
local  unpack		=  system.unpack
local tables		= require('useful.tables')

local  lstrip		= function(s) return (s:gsub('^%s*', '')) end
local  rstrip		= function(s) return (s:gsub('%s*$', '')) end
local  strip		= function(s) return lstrip(rstrip(s)) end
strings.lstrip		= lstrip
strings.rstrip		= rstrip
strings.strip		= strip
strings.join		= concat -- join(s, sep)

function strings.capitalize(s)
	return s:sub(1,1):upper() .. s:sub(2):lower()
end

function strings.split(s, sep, count)
	local fields = {}
	sep = sep or '%s+'
	count = count or #s
	local first, last
	local next = 0
	for _=1,count do
		first, last = s:find(sep, next + 1)
		if first == nil then break end
		insert(fields, s:sub(next + 1, first - 1))
		next = last
	end
	if next <= #s then
		insert(fields, s:sub(next + 1))
	end
	return fields
end

function strings.title(s)
	local fields = { }
	for i,field in ipairs(strings.split(s)) do
		fields[i] = strings.capitalize(field)
	end
	return strings.join(fields, ' ')
end

function strings.ljust(s, w, c)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return s .. rep(c or ' ', w-l)
	end
end

function strings.rjust(s, w, c)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return rep(c or ' ', w-l) .. s
	end
end

function strings.center(s, w, c)
	local l = #s
	if l > w then
		return s
	else
		local n = (w - l) / 2
		return rep(c or ' ', n) .. s .. rep(c or ' ', n)
	end
end

function strings.parse_ranges(str)
	local ranges = {}
	for _,range in ipairs(strings.split(str, ',')) do
		local ranges = tables.imap(strings.split(range, '-'),
			function (n, v)
				return n, tonumber(v)
			end)
		local s, e = unpack(ranges)
		e = e or s
		for i=s,e do
			insert(ranges, i)
		end
	end
	return ranges
end

function strings.hex_to_binary(s)
	local zero, nine = byte('0'), byte('9')
	local letter_a, letter_f = byte('a'), byte('f')
	local function add_ascii_hex(b, c)
		if zero <= c and c <= nine then
			return bor(lshift(b, 4), c - zero), true
		elseif letter_a <= c and c <= letter_f then
			return bor(lshift(b, 4), 10 + c - letter_a), true
		else
			return b, false
		end
	end
	local b, o = 0, 0
	local out = { }
	for i=1,#s do
		local c = byte(s:sub(i, i):lower())
		local is_hex
		b, is_hex = add_ascii_hex(b, c)
		if is_hex then
			if o == 1 then
				insert(out, char(b))
				b = 0
			end
			o = 1 - o
		end
	end
	return strings.join(out)
end

local hexs = '0123456789abcdef'
function strings.binary_to_hex(s, sep)
	local out = { }
	for i=1,#s do
		local c = byte(s:sub(i, i))
		local l = rshift(c, 4) + 1
		insert(out, hexs:sub(l, l))
		l = band(c, 0xf) + 1
		insert(out, hexs:sub(l, l))
		if sep then
			insert(out, sep)
		end
	end
	return strings.join(out)
end

function strings.hexdump(bytes, addr)
	local function hex_data(bytes, at_most) -- luacheck:ignore
		local hex = { }
		at_most = at_most or 16
		for i=1,math.min(#bytes, at_most) do
			local s -- luacheck:ignore
			s = sprintf("%02x", byte(bytes:sub(i,i)))
			insert(hex, s)
		end
		return concat(hex, ' ')
	end

	local function char_data(bytes) -- luacheck:ignore
		local s = ''
		for i=1,math.min(#bytes, 16) do
			local c = bytes:sub(i,i)
			if byte(c) < 32 or 127 < byte(c) then
				c = '.'
			end
			s = s .. c
		end
		return s
	end

	local lines = { }
	addr = addr or 0
	for off=1,#bytes,16 do
		local line
		line = sprintf("%06x: %-23s  %-23s | %s", addr + off -1,
			hex_data(bytes:sub(off,off+8-1), 8),
			hex_data(bytes:sub(off+8,off+16-1), 8),
			char_data(bytes:sub(off,off+16-1)))
		insert(lines, line)
	end
	return concat(lines, '\n')
end

return strings

