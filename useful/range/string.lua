--
-- u s e f u l / r a n g e / s t r i n g . l u a
--
local range_string = { }

local  byte	=  string.byte

local ffi	= require('ffi')
local  new	=  ffi.new

range_string.make_char_table = function(...)
	local char_table = new('char[256]')
	for _,char in ipairs({...}) do
		char_table[char] = 1
	end
	return char_table
end

range_string.make_char_table_func = function(func, ...)
	local char_table = range_string.make_char_table(...)
	return function(r)
		return func(r, char_table)
	end
end

range_string.make_find = function(...)
	return range_string.make_char_table_func(function(r, char_table)
		while not r:empty() and char_table[r:get_front()] == 0 do
			r:pop_front()
		end
		return r
	end, ...)
end

range_string.make_skip = function(...)
	return range_string.make_char_table_func(function(r, char_table)
		while not r:empty() and char_table[r:get_front()] == 1 do
			r:pop_front()
		end
		return r
	end, ...)
end

range_string.make_until = function(...)
	return range_string.make_char_table_func(function(r, char_table)
		local s = r:save()
		while not r:empty() and char_table[r:get_front()] == 0 do
			r:pop_front()
		end
		local found
		s.back = r.front
		-- move beyond the character found.
		if not r:empty() then
			found = r:get_front()
			r:pop_front()
		end
		return s, found
	end, ...)
end

local NL	= byte('\n')	range_string.NL		= NL
local CR	= byte('\r')	range_string.CR		= CR
local TAB	= byte('\t')	range_string.TAB	= TAB
local SPACE	= byte(' ')	range_string.SPACE	= SPACE
local AMP	= byte('&')	range_string.AMP	= AMP
local DOT	= byte('.')	range_string.DOT	= DOT
local SLASH	= byte('/')	range_string.SLASH	= SLASH
local COLON	= byte(':')	range_string.COLON	= COLON
local EQUALS	= byte('=')	range_string.EQUALS	= EQUALS
local PERCENT	= byte('%')	range_string.PERCENT	= PERCENT
local PLUS	= byte('+')	range_string.PLUS	= PLUS
local QUESTION	= byte('?')	range_string.QUESTION	= QUESTION

range_string.skip_ws = range_string.make_skip(SPACE, TAB, NL, CR)

local function merge_tables(...)
	local new_table		= range_string.make_char_table()
	for _,orig_table in ipairs({...}) do
		for c=0,255 do
			if orig_table[c] == 1 then
				new_table[c] = 1
			end
		end
	end
	return new_table
end
range_string.merge_tables = merge_tables

local lower		= range_string.make_char_table()
local upper		= range_string.make_char_table()
local numeric		= range_string.make_char_table()
local hexadecimal	= range_string.make_char_table()
for c=byte('0'),byte('9') do
	numeric[c]	= 1
	hexadecimal[c]	= 1
end
for c=byte('A'),byte('Z') do
	upper[c]	= 1
	if c <= byte('F') then hexadecimal[c] = 1 end
	c = c + byte('a') - byte('A')
	lower[c]	= 1
	if c <= byte('f') then hexadecimal[c] = 1 end
end
local alphanumeric	= merge_tables(numeric, lower, upper)
local alpha		= merge_tables(lower, upper)
range_string.alphanumeric	= alphanumeric
range_string.alpha		= alpha
range_string.upper		= upper
range_string.lower		= lower
range_string.numeric		= numeric
range_string.hexadecimal		= hexadecimal
range_string.is_alphanumeric 	= function(c) return alphanumeric[c] == 1 end
range_string.is_alpha		= function(c) return alpha[c] == 1 end
range_string.is_upper		= function(c) return upper[c] == 1 end
range_string.is_lower		= function(c) return lower[c] == 1 end
range_string.is_numeric		= function(c) return numeric[c] == 1 end
range_string.is_hexadecimal	= function(c) return hexadecimal[c] == 1 end

local end_of_line		= range_string.make_char_table(NL, CR)
range_string.end_of_line		= end_of_line
range_string.is_end_of_line	= function(c) return end_of_line[c] == 1 end

local whitespace		= range_string.make_char_table(SPACE, NL, CR, TAB)
range_string.whitespace		= whitespace
local is_whitespace		= function(c) return whitespace[c] == 1 end
range_string.is_whitespace	= is_whitespace

local rstrip = function(r)
	while not r:empty() and is_whitespace(r:get_back()) do
		r:pop_back()
	end
	return r
end
range_string.rstrip = rstrip

local lstrip = function(r)
	while not r:empty() and is_whitespace(r:get_front()) do
		r:pop_front()
	end
	return r
end
range_string.lstrip = lstrip

range_string.strip = function(r)
	return rstrip(lstrip(r))
end

return range_string

