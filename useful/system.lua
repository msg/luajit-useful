
local system = { }


require('useful.compatible')

system.unpack		= table.unpack			-- luacheck:ignore
system.pack		= table.pack			-- luacheck:ignore

system.loadstring	= loadstring or load		-- luacheck:ignore
system.getfenv		= getfenv
system.setfenv		= setfenv

function system.is_main()
        return debug.getinfo(4) == nil
end

return system
