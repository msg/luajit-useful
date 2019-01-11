
local system = { }

function system.is_main()
        return debug.getinfo(4) == nil
end

return system
