--
-- u s e f u l / c o m p a t i b l e . l u a
--

-- NOTE: This intentionally modifies lua `_G` and `table`.  It does both to
--       handle forwards and backwards compatibility.  `unpack()` is easy
--       because it always has existed.  `pack()` is not because it existed
--       in lua 5.2.  luajit *can* have 5.2 compatibility, but not all versions
--       have that enabled.

-- version	`unpack`	`table.unpack`	`pack`		`table.pack`
-- lua5.1 	function	nil		nil		nil
-- lua5.2	function	function	nil		function
-- lua5.3+	nil		function	nil		function
-- `loadstring`: lua5.1, lua5.2
-- `setfenv`, `getfenv`: lua5.1

--luacheck: push ignore
table.pack	= table.pack or function(...)
	local t = {...}
	t.n = select('#', ...)
	return t
end
table.unpack	= table.unpack or unpack
loadstring	= loadstring or load

setfenv = setfenv or function(fn, env)
	local i = 1
	while true do
		local name = getupvalue(fn, i)
		if name == '_ENV' then
			upvaluejoin(fn, i, function()
				return env
			end, 1)
			break
		elseif not name then
			break
		end
		i = i + 1
	end
	return fn
end

getfenv = getfenv or function(fn)
	local i = 1
	while true do
		local name, value = getupvalue(fn, i)
		if name == '_ENV' then
			return value
		elseif not name then
			break
		end
		i = i + 1
	end
end

-- luacheck: pop
