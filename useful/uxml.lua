#!/usr/bin/luajit

local uxml = {}

local  byte		=  string.byte
local  char		=  string.char
local  format		=  string.format
local  concat		=  table.concat
local  insert		=  table.insert
local  remove		=  table.remove
local  sort		=  table.sort

local node = { }
uxml.node = node
setmetatable(node, {
	__call = function(self, tag, attrs)
		return setmetatable({
			_tag		= tag or '',
			_attrs		= attrs or {},
			_children	= {},
		}, self)
	end,
})

local function is_node(o) return getmetatable(o) == node end
uxml.is_node = is_node

function node:__index(value)
	if node[value] then return node[value] end
	if type(value) == 'number' then
		return self._children[value]
	else
		local ret = {}
		for _,child in ipairs(self._children) do
			if child._tag == value then
				insert(ret, child)
			end
		end
		if #ret == 1 then
			return ret[1]
		elseif #ret > 1 then
			return ret
		end
	end
end
function node:__len()
	return #self._children
end
function node:add_child(child)
	if is_node(child) then
		rawset(child, '_parent', self)
	end
	insert(self._children, child)
end

local chars = { }
('\n\r'):gsub('.', function(c)
	chars[byte(c)] = format('&#x%X;', byte(c))
end)
local codes = { ['<']='lt',['>']='gt',['&']='amp', ["'"]='apos' }
local decode_chars = {}
for n,v in pairs(codes) do
	chars[byte(n)] = '&'..v..';'
	decode_chars[v] = byte(n)
end
uxml.chars = chars
local function decode(s)
	return s:gsub('%&([^;]+);', function(x)
		local b
		if x:sub(1,1) == '#' then
			if x:sub(2,2) == 'x' then
				b = tonumber(x:sub(3), 16)
			else
				b = tonumber(x:sub(2))
			end
		else
			b = decode_chars[x]
		end
		assert(b, 'invalid encoding &'..x..';')
		return char(b)
	end)
end
node.decode = decode
local function encode(s)
	return s:gsub('.', function(c)
		return chars[byte(c)] or c
	end)
end
node.encode = encode

function node:toxml(indent, trailer)
	indent = indent or ' '
	trailer = trailer or ''
	local attrs = ''
	local names = { }
	for name in pairs(self._attrs) do
		insert(names, name)
	end
	sort(names)
	for _,name in ipairs(names) do
		local value = self._attrs[name]
		attrs = attrs..' '..name..'="'..encode(value)..'"'
	end
	local strs = { }
	if self._header then
		indent = ''
		insert(strs, self._header..trailer)
	end
	if #self._children == 0 then
		return format('%s<%s%s/>%s', indent, self._tag, attrs, trailer)
	end
	if self._tag ~= '' then
		insert(strs, format('%s<%s%s>%s', indent, self._tag, attrs, trailer))
	end
	for _,n in ipairs(self._children) do
		if is_node(n) then
			insert(strs, n:toxml(indent..' ', trailer))
		else
			insert(strs, encode(n))
		end
	end
	if self._tag ~= '' then
		insert(strs, format('%s</%s>%s', indent, self._tag, trailer))
	end
	return concat(strs)
end

function node:walk(fn)
	fn(self)
	for _,n in ipairs(self._children) do
		if is_node(n) then
			n:walk(fn)
		end
	end
end

function node.fromxmlattrs(s)
	local attrs = {}
	string.gsub(s, "([%w_]+)=([\"'])(.-)%2", function (name, _, a)
		attrs[name] = decode(a)
	end)
	return attrs
end

function node.fromxml(xml)
	local top = node()
	local stack = { top }
	local curr = 1
	while true do
		local starts,ends,close,tag,attrs, empty = xml:find("<(%/?)([%w_:]+)(.-)(%/?)>", curr)
		if not starts then break end
		local text = xml:sub(curr, starts-1)
		if not string.find(text, "^%s*$") then
			if curr == 1 then
				top._header = text
			else
				top:add_child(decode(text))
			end
		end
		if close == '/' then
			local last = remove(stack)	-- remove top
			top = stack[#stack]
			if #stack < 1 then
				error("nothing to close with "..tag)
			end
			if last._tag ~= tag then
				error("trying to close "..last._tag.." with "..tag)
			end
			top:add_child(last)
		else
			attrs = top .fromxmlattrs(attrs)
			local n = node(tag, attrs)
			if empty == '/' then
				top:add_child(n)
			else
				top = n
				insert(stack, top)		-- new level
			end
		end
		curr = ends + 1
	end
	local text = xml:sub(curr)
	if not string.find(text, "^%s*$") then
		insert(stack[#stack], decode(text))
	end
	if #stack > 1 then
		error("unclosed "..stack[stack.n].tag)
	end
	return top
end

local function copy_node(orig)
	local new = node(orig._tag)
	rawset(new, '_header', orig._header)
	for n,v in pairs(orig._attrs) do
		new._attrs[n] = v
	end
	for _,child in pairs(orig._children) do
		local new_child = copy_node(child)
		new:add_child(new_child)
	end
	return new
end
uxml.copy_node = copy_node

return uxml

