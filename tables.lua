--
-- t a b l e s
--

module(..., package.seeall)

local insert = table.insert
local remove = table.remove

function serialize(o, indent, sp, nl)
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
				serialize(v, indent .. sp), ','
			}, ''))
		end
		insert(new, indent .. '}')
	else
		error('cannot serialize a ' ..type(o))
	end
	return table.concat(new, nl)
end

function unserialize(t)
	local func, err = loadstring('return ' .. t)
	if func ~= nil then
		setfenv(func, {})
		return func()
	end
	return nil
end

function save_table(filename, t)
	if not os or not os.loadAPI then
		filename = '../' .. filename
	end
	local f = io.open(filename, 'w')
	f:write(serialize(t))
	f:close()
end

function load_table(filename)
	if not os or not os.loadAPI then
		filename = '../' .. filename
	end
	local f = io.open(filename, 'r')
	if f == nil then
		return { }
	end
	local t = unserialize(f:read('*a'))
	f:close()
	return t
end

function count(t)
	local i = 0
	for _,_ in pairs(t) do
		i = i + 1
	end
	return i
end

function is_empty(t)
	return next(t) == nil
end

function in_table(t, e)
	for _,v in pairs(t) do
		if v == e then
			return true
		end
	end
	return false
end

function keys(t)
	local new = {}
	for n,_ in pairs(t) do
		insert(new, n)
	end
	return new
end

function concat(t, s)
	for _,v in ipairs(s) do
		insert(t, v)
	end
	return t
end

function copy(t)
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

function iiter(t)
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

function map(t, f)
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

function imap(t, f)
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

function find(t, f)
	for _,v in ipairs(t) do
		local result = f(v)
		if result ~= nil then
			return result
		end
	end
	return nil
end

function reverse(t)
	local new = {}
	for _,entry in ipairs(t) do
		insert(t, _, entry)
	end
	return new
end

function upper(t, i)
    if not i or i > #t then
        return #t
    elseif i < 0 then
        return #t + i + 1
    else
        return i
    end
end

function sub(t, s, e)
	e = upper(e)
	return { unpack(t, s or 1, e) }
end

function remove(t, s, e)
	e = upper(e)
	for i=s or 1,e do
		remove(t, s)
	end
end

function rep(value, count)
	local new = {}
	for i=1,count do
		insert(new, value)
	end
	return new
end

function range(first, last, inc)
	local new = {}
	inc = inc or 1
	for i=first,last,inc do
		insert(new, i)
	end
	return new
end

function update (t,...)
    for i=1,select('#',...) do
        for k,v in pairs(select(i,...)) do
            t[k] = v
        end
    end
    return t
end


--
--
--

function import(env, from, ...)
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

function select_entries(entries, title)
	local w, h = term.getSize()
	--local w, h = 80, 30
	--read = function() return io.stdin:read() end
	local t, dt, l, dl = 1, 0, 1, 0
	h = h - 2
	title = title .. ' ' or ''

	function find(entries, what, first, last, inc)
		if inc == nil then
			inc = 1
		end
		for i=first,last,inc do
			if entries[i]:find(what) then
				return i
			end
		end
		return 0
	end

	while true do
		t = math.min(math.max(t, 1), #entries-h)
		l = math.max(l, 1)
		local first=math.min(math.max(t, 1), #entries)
		local last=math.min(math.max(first+h, 1), #entries)

		for i=first,last do
			printf('%3d %s\n', i, entries[i]:sub(l,l+w-5))
		end
		percent = math.floor(1000*last/#entries)/10
		local s = 'h'
		local arg,n
		while s == 'h' do
			printf('%s(%.1f%%) h=help: ', title, percent)
			s = read()
			arg = s:sub(2)
			n = tonumber(arg) or 1
			s = s:sub(1,1)
			if s == 'h' then
				printf("[qtbnpduflr/?][*],ENT,#[-#]: ")
				s = read()
			end
		end
		local ranges = strings.parse_ranges(s..arg)
		if #ranges > 0 then
			return ranges
		elseif s == 'q' then return 0, 0
		elseif s == 't' then t = n
		elseif s == 'b' then t = #entries
		elseif s == 'n' then dt = n * h
		elseif s == 'p' then dt = -(n * h)
		elseif s == 'd' then dt = n
		elseif s == 'u' then dt = -n
		elseif s == 'f' then l = n
		elseif s == 'l' then dl = -5
		elseif s == 'r' then dl = 5
		elseif s == '/' then
			local i = find(entries, arg, t+1, #entries)
			if i > 0 then t = i end
		elseif s == '?' then
			local i = find(entries, arg, t-1, 1, -1)
			if i < 1 then
				i = find(entries, arg, #entries, t, -1)
			end
			if i > 0 then t = i end
		else		     dt = h
		end
		t = t + dt
		dt = 0
		l = l + dl
		dl = 0
	end
end

function enable_control_access(t)
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

function disable_control_access(t)
	setmetatable(t, {})
end

function structure(initializer)
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

	enable_control_access(self)

	return self
end

