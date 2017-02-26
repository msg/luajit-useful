--
-- s t r i n g s
--

module(..., package.seeall)

local gsub	= string.gsub
local rep	= string.rep
local insert	= table.insert

function lstrip(s) return gsub(s, '^%s*', '') end
function rstrip(s) return gsub(s, '%s*$', '') end
function strip(s) return gsub(gsub(s, '^%s*', ''), '%s*$', '') end
join = table.concat -- join(s, sep)

function capitalize(s)
	return s:sub(1,1):upper() .. s:sub(2)
end

function split(s, sep)
	local fields = {}
	sep = sep or '%s+'
	local first, last, next = 0, 0, 0
	while true do
		first, last = s:find(sep, next + 1)
		if first == nil then break end
		insert(fields, s:sub(next, first - 1))
		next = last
	end
	if next <= #s then
		insert(fields, s:sub(next + 1))
	end
	return fields
end

function ljust(s, w)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return s .. rep(' ', w-l)
	end
end

function rjust(s, w)
	local l = #s
	if l > w then
		return s:sub(1, w)
	else
		return rep(' ', w-l) .. s
	end
end

function center(s, w)
	local l = #s
	if l > w then
		return s
	else
		local n = (w - l) / 2
		return rep(' ', n) .. s .. rep(' ', n)
	end
end

function parse_ranges(s)
	local ranges = {}
	for _,range in ipairs(split(s, ',')) do
		local s, e = unpack(tables.imap(split(range, '-'),
				function (n,v) return tonumber(v) end))
		e = e or s
		for i=s,e do
			insert(ranges, i)
		end
	end
	return ranges
end

