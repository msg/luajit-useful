--
-- u s e f u l / t a b l e s . l u a
--
local tables = { }

local is_main	= require('useful.system').is_main

local insert = table.insert
local remove = table.remove

function tables.serialize(o, indent, sp, nl)
	local new = {}
	sp = sp or ' '
	ns = nl or '\n'
	indent = indent or ''
	if type(o) == 'number' then
		insert(new, tostring(o))
	elseif type(o) == 'string' then
		insert(new, string.format('%q', o))
	elseif type(o) == 'table' then
		insert(new, '{')
		local last = 0
		for k,v in pairs(o) do
			if type(k) == 'string' then
				k = k .. ' = '
			elseif type(k) == 'number'  then
				if last == k - 1 then
					last = k
					k = ''
				else
					last = nil
					k = '[' .. k .. '] = '
				end
			end
			insert(new, table.concat({
				indent, sp, k,
				tables.serialize(v, indent .. sp), ','
			}, ''))
		end
		insert(new, indent .. '}')
	else
		error('cannot serialize a ' ..type(o))
	end
	return table.concat(new, nl)
end

function tables.unserialize(t)
	local func, err = loadstring('return ' .. t)
	if func ~= nil then
		setfenv(func, {})
		return func()
	end
	return nil
end

function tables.save_table(filename, t)
	local f = io.open(filename, 'w')
	f:write(tables.serialize(t))
	f:close()
end

function tables.load_table(filename)
	local f = io.open(filename, 'r')
	if f == nil then
		return { }
	end
	local t = tables.unserialize(f:read('*a'))
	f:close()
	return t
end

function tables.count(t)
	local i = 0
	for _,_ in pairs(t) do
		i = i + 1
	end
	return i
end

function tables.is_empty(t)
	return next(t) == nil
end

function tables.in_table(t, e)
	for _,v in pairs(t) do
		if v == e then
			return true
		end
	end
	return false
end

function tables.keys(t)
	local new = {}
	for n,_ in pairs(t) do
		insert(new, n)
	end
	return new
end

function tables.concat(t, s)
	for _,v in ipairs(s) do
		insert(t, v)
	end
	return t
end

function tables.copy(t)
	local new = {}
	for n,v in pairs(t) do
		if type(v) == 'table' then
			new[n] = tables.copy(v)
		else
			new[n] = v
		end
	end
	return new
end

function tables.iiter(t)
	local i = 0
	return function()
		i = i + 1
		if t[i] then
			return i, t[i]
		else
			return nil
		end
	end
end

function tables.map(t, f)
	if t == nil then
		error('map(t,f) t is nil', 2)
	end
	local new = {}
	for n,v in pairs(t) do
		n, v = f(n, v)
		if n ~= nil then
			new[n] = v
		end
	end
	return new
end

function tables.imap(t, f)
	if t == nil then
		error('imap(t,f) t is nil', 2)
	end
	local new = {}
	for n,v in ipairs(t) do
		local v = f(n, v)
		if v ~= nil then
			insert(new, v)
		end
	end
	return new
end

function tables.find(t, f)
	for _,v in ipairs(t) do
		local result = f(v)
		if result ~= nil then
			return result
		end
	end
	return nil
end

function tables.reverse(t)
	local new = {}
	for _,entry in ipairs(t) do
		insert(new, _, entry)
	end
	return new
end

function tables.upper(t, i)
	if not i or i > #t then
		return #t
	elseif i < 0 then
		return #t + i + 1
	else
		return i
	end
end

function tables.sub(t, s, e)
	s = upper(s or 1)
	e = upper(e)
	return { unpack(t, s, e) }
end

function tables.remove(t, s, e)
	s = upper(s or 1)
	e = upper(e)
	for i=s,e do
		remove(t, s)
	end
end

function tables.rep(value, count)
	local new = {}
	for i=1,count do
		insert(new, value)
	end
	return new
end

function tables.range(first, last, inc)
	local new = {}
	inc = inc or 1
	for i=first,last,inc do
		insert(new, i)
	end
	return new
end

function tables.update(t,...)
	for i=1,select('#',...) do
		for k,v in pairs(select(i,...)) do
			t[k] = v
		end
	end
	return t
end

function tables.import(env, from, ...)
	local vars = {...}
	if #vars ~= 0 then
		for _,n in ipairs(vars) do
			env[n] = from[n]
		end
	else
		for n,v in pairs(from) do
			env[n] = v
		end
	end
end

function tables.enable_control_access(t)
	-- metatable controls
	local mt = {}
	function mt.__newindex(_, n)
		error('attempt to write an undeclared member "'..n..'"', 2)
	end
	function mt.__index(_, n)
		error('attempt to read an undeclared member "'..n..'"', 2)
	end
	setmetatable(t, mt)

	return t
end

function tables.disable_control_access(t)
	setmetatable(t, nil)
end

function tables.structure(initializer)
	local self = initializer or {}

	-- add/clear member variable
	function self.add_members(t)
		for n,v in pairs(t) do
			if v == nil then
				error('attempt to set member ' .. name ..
					' to nil', 2)
			end
			rawset(self, n, v)
		end
	end

	function self.clear_member(name)
		rawset(self, name, nil)
	end

	tables.enable_control_access(self)

	return self
end

local function main()
end

if is_main() then
	main()
else
	return tables
end

