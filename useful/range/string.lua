--
-- u s e f u l / r a n g e / s t r i n g . l u a
--

local rangestring = { }

local  byte	=  string.byte

local ffi	= require('ffi')
local  new	=  ffi.new

rangestring.make_char_table = function(...)
	local char_table = new('char[256]')
	for _,char in ipairs({...}) do
		char_table[char] = 1
	end
	return char_table
end

rangestring.make_char_table_func = function(func, ...)
	local char_table = rangestring.make_char_table(...)
	return function(r)
		return func(r, char_table)
	end
end

rangestring.make_find = function(...)
	return rangestring.make_char_table_func(function(r, char_table)
		while not r:empty() and char_table[r:get_front()] == 0 do
			r:pop_front()
		end
		return r
	end, ...)
end

rangestring.make_skip = function(...)
	return rangestring.make_char_table_func(function(r, char_table)
		while not r:empty() and char_table[r:get_front()] == 1 do
			r:pop_front()
		end
		return r
	end, ...)
end

rangestring.make_until = function(...)
	return rangestring.make_char_table_func(function(r, char_table)
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

local NL	= byte('\n')	rangestring.NL		= NL
local CR	= byte('\r')	rangestring.CR		= CR
local TAB	= byte('\t')	rangestring.TAB		= TAB
local SPACE	= byte(' ')	rangestring.SPACE	= SPACE
local AMP	= byte('&')	rangestring.AMP		= AMP
local DOT	= byte('.')	rangestring.DOT		= DOT
local SLASH	= byte('/')	rangestring.SLASH	= SLASH
local COLON	= byte(':')	rangestring.COLON	= COLON
local EQUALS	= byte('=')	rangestring.EQUALS	= EQUALS
local PERCENT	= byte('%')	rangestring.PERCENT	= PERCENT
local PLUS	= byte('+')	rangestring.PLUS	= PLUS
local QUESTION	= byte('?')	rangestring.QUESTION	= QUESTION

rangestring.skip_ws = rangestring.make_skip(SPACE, TAB, NL, CR)

local function merge_tables(...)
	local new_table		= rangestring.make_char_table()
	for _,orig_table in ipairs({...}) do
		for c=0,255 do
			if orig_table[c] == 1 then
				new_table[c] = 1
			end
		end
	end
	return new_table
end
rangestring.merge_tables = merge_tables

local lower		= rangestring.make_char_table()
local upper		= rangestring.make_char_table()
local numeric		= rangestring.make_char_table()
local hexadecimal	= rangestring.make_char_table()
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
local alphanumeric		= merge_tables(numeric, lower, upper)
local alpha			= merge_tables(lower, upper)
rangestring.alphanumeric	= alphanumeric
rangestring.alpha		= alpha
rangestring.upper		= upper
rangestring.lower		= lower
rangestring.numeric		= numeric
rangestring.hexadecimal		= hexadecimal
rangestring.is_alphanumeric 	= function(c) return alphanumeric[c] == 1 end
rangestring.is_alpha		= function(c) return alpha[c] == 1 end
rangestring.is_upper		= function(c) return upper[c] == 1 end
rangestring.is_lower		= function(c) return lower[c] == 1 end
rangestring.is_numeric		= function(c) return numeric[c] == 1 end
rangestring.is_hexadecimal	= function(c) return hexadecimal[c] == 1 end

local end_of_line		= rangestring.make_char_table(NL, CR)
rangestring.end_of_line		= end_of_line
rangestring.is_end_of_line	= function(c) return end_of_line[c] == 1 end

local whitespace		= rangestring.make_char_table(SPACE, NL, CR, TAB)
rangestring.whitespace		= whitespace
local is_whitespace		= function(c) return whitespace[c] == 1 end
rangestring.is_whitespace	= is_whitespace

local rstrip = function(r)
	while not r:empty() and is_whitespace(r:get_back()) do
		r:pop_back()
	end
	return r
end
rangestring.rstrip = rstrip

local lstrip = function(r)
	while not r:empty() and is_whitespace(r:get_front()) do
		r:pop_front()
	end
	return r
end
rangestring.lstrip = lstrip

rangestring.strip = function(r)
	lstrip(r)
	rstrip(r)
	return r
end

return rangestring

