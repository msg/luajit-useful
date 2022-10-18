#!/usr/bin/luajit

local h = { }

local  type	=  type
local  rep	=  string.rep
local  join	=  table.concat
local  insert	=  table.insert

local function copy(to, ...)
	for _,from in ipairs({...}) do
		for k,v in pairs(from) do
			to[k] = v
		end
	end
	return to
end

local function class(impl)
	impl.__index	= impl

	return setmetatable(impl, {
		__call = function (impl, ...) -- luacheck: ignore
			local instance = setmetatable({ _impl=impl }, impl)
			-- run the new method if it's there
			if impl.new then
				impl.new(instance, ...)
			end
			return instance
		end
	})
end

-- not used yet: TODO replace is_* below
local function is_a(impl, object) return object._impl == impl end --luacheck:ignore

local NODE, ATTRIBUTE, MARKER = 1, 2, 3

local function is_function(o)	return type(o) == 'function' end
local function is_node(o)	return o.type == NODE end
local function is_attribute(o)	return o.type == ATTRIBUTE end
local function is_marker(o)	return o.type == MARKER end --luacheck:ignore

function h.map(t, f)
	local new = { }
	for n,v in pairs(t) do
		insert(new, f(v, n))
	end
	return new
end

function h.bind(func, first)
	return function(...)
		return func(first, ...)
	end
end

function h.merge_array(to, from)
	for _,e in ipairs(from) do
		insert(to, e)
	end
	return to
end

local function merge_lines(to, from)
	for _,line in ipairs(from) do
		if #line ~= 0 then
			insert(to, line)
		end
	end
end

local function child_lines(node, children, indent)
	local lines = { }
	for _,child in ipairs(children) do
		-- must check and call function here as is_node() uses table
		if is_function(child) then
			merge_lines(lines, child_lines(node, child(), indent))
		elseif is_node(child) then
			child.indent = node.indent + indent
			merge_lines(lines, child:lines())
		else
			insert(lines, child)
		end
	end
	return lines
end

h.indent_char = ' '

local Node = class({
	new = function(self, name, ...)
		self.type		= NODE
		self.indent		= 0
		self.name		= name
		self.content		= { }

		self:add(...)
	end,

	__tostring = function(self)
		return self:render()
	end,

	lines = function(self)
		return child_lines(self, self.content, 0)
	end,

	add = function(self, ...)
		h.merge_array(self.content, {...})
		return self
	end,

	render = function(self)
		return join(self:lines(), '\n')
	end,
})
h.Node = Node

local tag = class(copy({}, Node, {
	new = function(self, name, ...)
		self.indent		= 1
		self.attributes		= { }
		self.attribute_indexes	= { }
		Node.new(self, name, ...)
	end,

	update_attribute = function(self, attribute)
		local index = self.attribute_indexes[attribute.name]
		if index == nil then
			insert(self.attributes, attribute)
			index = #self.attributes
			self.attribute_indexes[attribute.name] = index
		else
			local value = self.attributes[index].value
			self.attributes[index].value =
					value .. ' ' .. attribute.value
		end
	end,

	start_tag = function(self)
		local attributes = ''
		if #self.attributes > 0 then
			attributes = h.map(self.attributes, tostring)
			attributes = ' ' .. join(attributes, ' ')
		end
		return '<' .. self.name .. attributes .. '>'
	end,

	end_tag = function(self)
		return '</' .. self.name .. '>'
	end,

	lines = function(self)
		local indent = rep(h.indent_char, self.indent)
		local start_tag = indent .. self:start_tag()
		local end_tag = self:end_tag()

		local lines = child_lines(self, self.content, 1)
		if #lines == 0 then
			lines = { start_tag .. end_tag }
		elseif #lines == 1 then
			lines[1] = lines[1]:gsub('^%s+','')
			lines = { start_tag .. lines[1] .. end_tag }
		else
			insert(lines, 1, start_tag)
			insert(lines, indent .. end_tag)
		end

		return lines
	end,

	render = function(self)
		return join(self:lines(), '\n')
	end,

	add = function(self, ...)
		for _,arg in ipairs({...}) do
			-- must check function here as is_attribute uses table
			if is_function(arg) then
				insert(self.content, arg)
			elseif is_attribute(arg) then
				self:update_attribute(arg)
			else
				insert(self.content, arg)
			end
		end
		return self
	end,
}))
h.tag = tag

local single_tag = class(copy({}, tag, {
	lines = function(self)
		return { self:render() }
	end,

	render = function(self)
		local indent = rep(h.indent_char, self.indent)
		return indent .. self:start_tag()
	end,

}))
h.single_tag = single_tag

local attribute = class({
	new = function(self, name, value)
		self.type	= ATTRIBUTE
		self.name	= name
		self.value	= value
	end,

	__tostring = function(self)
		return self.name .. '="' .. self.value .. '"'
	end,
})

-- prepend '-' for single node (no </end>)
-- prepend '/' for single node with trailing '/' ie. <one/>
local tags = {
	-- main html stuff
	'html', 'head', 'body', 'title',
	'header',
	-- links, img
	'a', '-img',
	-- regular
	'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
	'ital', 'i', 'bold', 'b', 'font', 'p', 'pre', '-br', '-hr',
	'em', 'strong', 'small', 'abbr', 'sup', 'sub',
	'ins', 'kbd', 'label', 'mark', 'del',
	-- table
	'table', 'caption', 'th', 'tr', 'td', 'thead', 'tbody',
	-- lists
	'ul', 'li',
	'dl', 'dd', 'dt',
	'ol', 'ul', 'li',
	-- frame/div
	'frame', 'div', 'span',
	-- forms
	'form', '-input', 'button',
	-- css scripting
	'-meta', '-link', 'script',
}
h.tags = tags

for _,name in ipairs(tags) do
	if name:sub(1,1) == '-' then
		name = name:sub(2)
		h[name] = h.bind(single_tag, name)
	else
		h[name] = h.bind(tag, name)
	end
end

h.doctype = function(name)
	local items = { '!DOCTYPE', name }
	return single_tag(join(items, ' '))
end

h.comment = function(content)
	local self = single_tag('!--', content)
	function self.lines(node)
		local indent = rep(h.indent_char, node.indent)
		return { indent .. '<!-- ' .. join(node.content) .. ' -->' }
	end
	return self
end

local attributes = {
	'class', 'id', 'style',
	'rel', 'src', 'ref', 'href',
	'lang', 'charset',
	'name', 'content',
	'type',
}
h.attributes = attributes

for _,name in ipairs(attributes) do
	h[name] = h.bind(attribute, name)
end

h.data = function(rest, ...) -- data-node
	return attribute('data-'..rest, ...)
end

h.container = function(...)
	return Node('container', ...)
end

function h.document(format, lang)
	local html = h.html(h.lang(lang))
	local self = h.container(h.doctype(format), html)
	self.html = html
	return self
end

function h.inline(func)
	local node = h.container()
	return function()
		func(node)
		return { node }
	end
end

function h.global()
	setmetatable(_G, { __index = h })
end

local function test(n)
	local doc = h.document('html', 'en')
	local head = h.head(
		h.title('HTML Example'),
		h.meta(h.charset'utf-8'),
		h.meta(h.name'viewport', h.content'width=device-width,initial-scale=1'),
		h.link(h.rel'stylesheet', h.href'css/template.css')
	)
	local body = h.body(
		h.h1('Test inline',h.class'inline'),
		h.inline(function(node)
			for i=1,n do
				node:add(h.p('testing '..i))
			end
		end)
	)
	doc.html:add(head, body)
	return doc:render()
end

local function main()
	print(test(10))
end

local function is_main()
	return debug.getinfo(4) == nil
end

if is_main() then
	main()
end


return h
