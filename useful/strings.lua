--
-- u s e f u l / s t r i n g s . l u a
--
local strings = { }

local  abs		=  math.abs
local  max		=  math.max
local  min		=  math.min

local  byte		=  string.byte
local  char		=  string.char
local  format		=  string.format
local  rep		=  string.rep

local  insert		=  table.insert
local  concat		=  table.concat

local bit		= require('bit')
local  bor		=  bit.bor
local  band		=  bit.band
local  lshift		=  bit.lshift
local  rshift		=  bit.rshift

			  require('useful.compatible')
local  unpack		=  table.unpack			-- luacheck:ignore
local tables		= require('useful.tables')
local  serialize	=  tables.serialize
local  deserialize	=  tables.deserialize

local  lstrip		= function(s) return (s:gsub('^%s*', '')) end
local  rstrip		= function(s) return (s:gsub('%s*$', '')) end
local  strip		= function(s) return lstrip(rstrip(s)) end
strings.lstrip		= lstrip
strings.rstrip		= rstrip
strings.strip		= strip
strings.join		= concat -- join(s, sep)

local function capitalize(s)
	return s:sub(1,1):upper() .. s:sub(2):lower()
end
strings.capitalize = capitalize

local function split(s, sep, count)
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
strings.split = split

function strings.title(s)
	local fields = { }
	for i,field in ipairs(split(s)) do
		fields[i] = capitalize(field)
	end
	return concat(fields, ' ')
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

function strings.parse_ranges(str, first, last)
	local ranges = {}
	for _,range in ipairs(split(str, ',')) do
		local s, e = unpack(split(range, '-'))
		s = s == '' and first or tonumber(s)
		e = e == '' and last  or tonumber(e)
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
	return concat(out)
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
	return concat(out)
end

function strings.hexdump(bytes, addr)
	local function hex_data(bytes, at_most) -- luacheck:ignore
		local hex = { }
		at_most = at_most or 16
		for i=1,min(#bytes, at_most) do
			local s -- luacheck:ignore
			s = format("%02x", byte(bytes:sub(i,i)))
			insert(hex, s)
		end
		return concat(hex, ' ')
	end

	local function char_data(bytes) -- luacheck:ignore
		local s = ''
		for i=1,min(#bytes, 16) do
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
		line = format("%06x: %-23s  %-23s | %s", addr + off -1,
			hex_data(bytes:sub(off,off+8-1), 8),
			hex_data(bytes:sub(off+8,off+16-1), 8),
			char_data(bytes:sub(off,off+16-1)))
		insert(lines, line)
	end
	return concat(lines, '\n')
end

function strings.serialize(t, indent, sp, nl, visited)
	return serialize(t, indent or '', sp or '', nl or '', visited)
end

function strings.deserialize(s)
	return deserialize(s)
end

function strings.expand(s, ...)
	local env = { args = {...} }
	local mt = _G
	if type(env.args[1]) == 'table' then
		mt = table.remove(env.args, 1)
	end
	setmetatable(env, { __index = mt })
	local do_eval = function(expr)
		if env[expr] ~= nil then
			return tostring(env[expr])
		else
			local f = loadstring('return '..tostring(expr))
			if not f then
				return expr
			end
			setfenv(f, env)
			return f()
		end
	end
	s = s:gsub('$%b{}', function(var)
		return do_eval(var:sub(3,-2), env)
	end)
	return s
end

-- NOTE: uppercase is log2 and lowercase is log10
local si_units = {
	E = lshift(1LL, 60),
	P = lshift(1LL, 50),
	T = lshift(1LL, 40),
	G = lshift(1LL, 30),
	M = lshift(1LL, 20),
	K = lshift(1LL, 10),
	e = 1000LL * 1000LL * 1000LL * 1000LL * 1000LL * 1000LL,
	p = 1000LL * 1000LL * 1000LL * 1000LL * 1000LL,
	t = 1000LL * 1000LL * 1000LL * 1000LL,
	g = 1000LL * 1000LL * 1000LL,
	m = 1000LL * 1000LL,
	k = 1000LL,
}
strings.si_units = si_units

function strings.parse_si_units(s)
	local n, e	= s:match('(%d+)(.?)')
	return tonumber(n) * (si_units[e] or 1)
end

function strings.format_engineering(value, places)
	places		= places or 3
        local prefixes	= 'qryzafpnum kMGTPEZYRQ'
        local p		= 11
        local neg

        if value < 0 then
                neg = '-'
        else
                neg = ' '
        end
        value = abs(value)

        while p > 0 and value ~= 0.0 and value < 1.0 do
                value = value * 1000.0
                p = p - 1
        end

        while p < #prefixes and value ~= 0.0 and value > 1000.0 do
                value = value / 1000.0
                p = p + 1
        end

        if value >= 100.0 then
                places = places - 2
        elseif value >= 10.0 then
                places = places - 1
        end

        places = max(places, 1)
        local fmt = format('%%.%df%%s', places)
        return format(neg .. fmt, value, prefixes:sub(p,p))
end

return strings

