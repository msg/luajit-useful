#!/usr/bin/env luajit

local csv = { }

local find	= string.find
local gsub	= string.gsub
local sub	= string.sub
local insert	= table.insert

-- Used to escape "'s by to()
local function escape(s)
	if find(s, '[,"]') then
		s = '"' .. gsub(s, '"', '""') .. '"'
	end
	return s
end
csv.escape = escape

-- Convert from table to csv string
csv.to = function(from)
	local to = {}
	for _,p in ipairs(from) do
		insert(to, escape(p))
	end
	return table.concat(to, ',')
end

-- Convert from csv string to table (converts a single line of a csv file)
csv.from = function(s)
	local t		= {}
	local start	= 1
	s = s .. ','				-- ending comma
	repeat
		-- next field is quoted? (start with `"'?)
		if find(s, '^"', start) then
			local c
			local i = start
			repeat
				-- find closing quote
				_, i, c = find(s, '"("?)', i+1) --luacheck:ignore
			until c ~= '"'		-- quote not followed by quote?
			if not i then error('unmatched "') end
			local f = sub(s, start+1, i-1)
			insert(t, (gsub(f, '""', '"')))
			start = find(s, ',', i) + 1
		else				-- unquoted; find next comma
			local nexti = find(s, ',', start)
			insert(t, sub(s, start, nexti-1))
			start = nexti + 1
		end
	until start > #s
	return t
end

return csv
