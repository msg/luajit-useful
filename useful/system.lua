
local system = { }

function system.is_main()
        return debug.getinfo(4) == nil
end

system.unpack	= unpack or table.unpack

system.loadstring = loadstring or load -- luacheck:ignore

system.setfenv = setfenv or function(fn, env) -- luacheck:ignore
	local i = 1
	while true do
		local name = debug.getupvalue(fn, i)
		if name == '_ENV' then
			debug.upvaluejoin(fn, i, function() -- luacheck:ignore
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

system.getfenv = getfenv or function(fn) -- luacheck:ignore
	local i = 1
	while true do
		local name, value = debug.getupvalue(fn, i)
		if name == '_ENV' then
			return value
		elseif not name then
			break
		end
		i = i + 1
	end
end

return system
