--
-- u s e f u l / t a b l e s . l u a
--
local tables = { }

local  insert	=  table.insert
local  concat	=  table.concat

local system	= require('useful.system')
local  is_main	=  system.is_main
local  setfenv	=  system.setfenv

local function is_identifier(s)
	return s:match('^[_A-Za-z][_A-Za-z0-9]*$') ~= nil
end

local function encode(s)
	local data = string.format('%q', s)
	return data
end

local function serialize(o, indent, sp, nl, visited)
	local new = {}
	visited = visited or { }
	sp = sp or ' '
	nl = nl or '\n'
	indent = indent or ''
	local otype = type(o)
	if otype == 'number' or otype == 'boolean' then
		insert(new, tostring(o))
	elseif otype == 'string' then
		insert(new, encode(o))
	elseif otype == 'table' then
		if visited[o] == true then
			error('table loop')
		end
		visited[o] = true
		insert(new, '{')
		local last = 0
		for k,v in pairs(o) do
			local ktype = type(k)
			if ktype == 'string' then
				if not is_identifier(k) then
					k = '['..encode(k)..']'
				end
				k = k..sp..'='..sp
			elseif ktype == 'boolean'  then
				k = '['..tostring(k)..']'..sp..'='..sp
			elseif ktype == 'number'  then
				if last + 1 == k then
					last = k
					k = ''
				else
					last = 0
					k = '['..k..']'..sp..'='..sp
				end
			end
			v = serialize(v, indent .. sp, sp, nl, visited)
			insert(new, concat({ indent, sp, k, v, ',' }, ''))
		end
		insert(new, indent .. '}')
	else
		error('cannot serialize a ' ..type(o))
	end
	return concat(new, nl)
end
tables.serialize = serialize

function tables.deserialize(t)
	local func, err = loadstring('return ' .. t) -- luacheck: ignore
	if func ~= nil then
		setfenv(func, {})
		return func()
	end
	return nil
end
tables.unserialize = tables.deserialize

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
	local data = f:read('*a')
	f:close()
	return tables.unserialize(data)
end

local function pack(...)
	local new = {...}
	new.n = select('#', ...)
	return new
end
tables.pack	= table.pack or pack		-- luacheck:ignore
tables.unpack	= unpack or table.unpack	-- luacheck:ignore

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

function tables.values(t)
	local new = {}
	for _,v in pairs(t) do
		insert(new, v)
	end
	return new
end

function tables.concat(t, s)
	for _,v in ipairs(s) do
		insert(t, v)
	end
	return t
end

local copy
copy = function(t)
	local new = {}
	for n,v in pairs(t) do
		if type(v) == 'table' then
			new[n] = copy(v)
		else
			new[n] = v
		end
	end
	return new
end
tables.copy = copy

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

function tables.map(t, f, it)
	assert(t, 'map(t, f[, it]) t is nil')
	local new = {}
	it = it or pairs
	for n,v in it(t) do
		n, v = f(n, v)
		if n ~= nil then
			new[n] = v
		end
	end
	return new
end

function tables.imap(t, f)
	assert(t, 'map(t, f) t is nil')
	return tables.map(t, f, ipairs)
end

function tables.index(t, value)
	local compare = type(value) == 'function' and value or
			function(v) return v == value end
	for n,v in ipairs(t) do
		if compare(v) then
			return n, v
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

local function offset(t, i)
	if not i or i > #t then
		return #t
	elseif i < 0 then
		return #t + i + 1
	else
		return i
	end
end
tables.offset = offset

function tables.sub(t, s, e)
	s = offset(t, s or 1)
	e = offset(t, e)
	return { unpack(t, s, e) }
end

function tables.iremove(t, keep, s, e)
	s = offset(t, s or 1)
	e = offset(t, e)
	for i=s,e do
		if keep(t, i, s) then
			if i ~= s then -- differing iter and insert point
				t[s] = t[i]
				t[i] = nil
			end
			s = s + 1 -- next insert point
		else
			t[i] = nil
		end
	end
	return t
end

function tables.rep(value, count)
	local new = {}
	for _=1,count do
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

function tables.update(t, ...)
	local a = tables.pack(...)
	for i=1,a.n do
		for k,v in pairs(a[i]) do
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
				error('attempt to set member ' .. n ..
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

