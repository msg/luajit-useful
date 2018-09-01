--
-- u s e f u l / s t r i n g s . l u a
--

module(..., package.seeall)

local bit		= require('bit')
local bor, band		= bit.bor, bit.band
local lshift, rshift	= bit.lshift, bit.rshift
local insert, concat	= table.insert, table.concat
local byte, char	= string.byte, string.char
local gsub, rep		= string.gsub, string.rep
local tables		= require('useful.tables')

function lstrip(s) return gsub(s, '^%s*', '') end
function rstrip(s) return gsub(s, '%s*$', '') end
function strip(s) return gsub(gsub(s, '^%s*', ''), '%s*$', '') end
join = table.concat -- join(s, sep)

function capitalize(s)
	return s:sub(1,1):upper() .. s:sub(2):lower()
end

function split(s, sep, count)
	local fields = {}
	sep = sep or '%s+'
	count = count or #s
	local first, last, next = 0, 0, 0
	for i=1,count do
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

function title(s)
	local fields = { }
	for i,field in ipairs(split(s)) do
		fields[i] = capitalize(field)
	end
	return join(fields, ' ')
end

function ljust(s, w, c)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return s .. rep(c or ' ', w-l)
	end
end

function rjust(s, w, c)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return rep(c or ' ', w-l) .. s
	end
end

function center(s, w, c)
	local l = #s
	if l > w then
		return s
	else
		local n = (w - l) / 2
		return rep(c or ' ', n) .. s .. rep(c or ' ', n)
	end
end

function parse_ranges(s)
	local ranges = {}
	for _,range in ipairs(split(s, ',')) do
		local s, e = unpack(
			tables.imap(split(range, '-'), function (n,v)
				return tonumber(v)
			end)
		)
		e = e or s
		for i=s,e do
			insert(ranges, i)
		end
	end
	return ranges
end

function hex_to_binary(s)
	local zero, nine = byte('0'), byte('9')
	local letter_a, letter_f = byte('a'), byte('f')
	function add_ascii_hex(b, c)
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
		b, is_hex = add_ascii_hex(b, c)
		if is_hex then
			if o == 1 then
				insert(out, char(b))
				b = 0
			end
			o = 1 - o
		end
	end
	return join(out)
end

local hexs = '0123456789abcdef'
function binary_to_hex(s, sep)
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
	return join(out)
end
