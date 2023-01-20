--
-- u s e f u l / t a b l e s . l u a
--
local tables = { }

local  insert	=  table.insert
local  concat	=  table.concat

local system	= require('useful.system')
local  pack	=  system.pack
local  setfenv	=  system.setfenv
local  unpack	=  system.unpack

local function is_identifier(s)
	return s:match('^[_A-Za-z][_A-Za-z0-9]*$') ~= nil
end

local keywords = {}
for _,keyword in ipairs({ 'function', 'end', 'do', 'while', 'repeat',
			'until', 'if', 'then', 'else', 'elseif', 'for',
			'in', 'function', 'local', 'return', 'break',
			'continue', 'false', 'true', 'nil', }) do
	keywords[keyword] = true
end

local function is_keyword(s)
	return keywords[s] ~= nil
end

local function encode(s)
	local data = string.format('%q', s)
	return data
end

local serialize_entry

local serialize_table = function(t, indent, sp, nl, unknown_ok)
	local new = { }
	insert(new, '{')
	local prev = 0
	for _,kv in ipairs(t) do
		local kt, k, vt, v = unpack(kv)
		k, prev = handle_table_key(kt, k, prev, unknown_ok)
		if k ~= '' then
			k = k..sp..'='..sp
		end
		v = serialize_entry(vt, v, indent, sp, nl, unknown_ok)
		insert(new, concat({ indent, sp, k, v, ',' }, ''))
	end
	insert(new, indent..'}')
	local s = concat(new, nl)
	local ns = s:gsub('%s+', ' ')
	if #ns < 80 then
		s = ns
	end
	return s
end

serialize_entry = function(et, e, indent, sp, nl, unknown_ok)
	local new = { }
	if et == 'table' then
		insert(new, serialize_table(e, indent, sp, nl, unknown_ok))
	elseif et == 'string' or et == 'boolean' or et == 'number' then
		insert(new, e)
	elseif unknown_ok then
		insert(new, e)
	else
		error('cannot serialize a '..et)
	end
	return concat(new, nl)
end

local serialize = function(o, indent, sp, nl, unknown_ok)
	sp = sp or ' '
	nl = nl or '\n'
	indent = indent or ''
	local et, e = unpack(build_entry(o))
	return serialize_entry(et, e, indent, sp, nl, unknown_ok)
end
tables.serialize = serialize

local linearize_table
linearize_table = function(e, leader, unknown_ok, new)
	new = new or { leader..' = {}'}
	leader = leader or ''
	for _,kv in ipairs(e) do
		local kt, k, vt, v = unpack(kv)
		local prev --luacheck:ignore
		k, prev = handle_table_key(kt, k, -1, unknown_ok)
		if k:sub(1,1) == '[' then --luacheck:ignore
		elseif k == '' then
			k = '['..k..']'
		else
			k = '.'..k
		end
		local name = leader..k
		if vt == 'table' then
			insert(new, name..' = {}')
			linearize_table(v, name, unknown_ok, new)
		else
			insert(new, name..' = '..v)
		end
	end
	table.sort(new)
	return new
end

local linearize = function(t, leader, unknown_ok)
	local et, e = unpack(build_entry(t))
	if et == 'table' then
		return concat(linearize_table(e, leader, unknown_ok), '\n')
	else
		error('cannot linearize a '..et)
	end
end
tables.linearize = linearize

local deserialze = function(t)
	local func, err = loadstring('return ' .. t) -- luacheck: ignore
	if func ~= nil then
		setfenv(func, {})
		return func()
	end
	return nil
end
tables.deserialize = deserialize
tables.unserialize = deserialize

function tables.save_table(filename, t)
	local f = io.open(filename, 'w')
	f:write(serialize(t))
	f:close()
end

function tables.load_table(filename)
	local f = io.open(filename, 'r')
	if f == nil then
		return { }
	end
	local data = f:read('*a')
	f:close()
	return unserialize(data)
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
	if i < 0 then
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
	local a = pack(...)
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

return tables

