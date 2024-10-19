
local system = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  errno		=  ffi.errno
local  fstring		=  ffi.string

			  require('useful.compatible')

system.unpack		= table.unpack			-- luacheck:ignore
system.pack		= table.pack			-- luacheck:ignore

system.loadstring	= loadstring or load		-- luacheck:ignore
system.getfenv		= getfenv
system.setfenv		= setfenv

function system.errno_string(err)
	err = err or errno()
	return tostring(err)..' '..fstring(C.strerror(err))
end

function system.is_main()
        return debug.getinfo(4) == nil
end

function system.add_path(path)
	package.path = package.path..';'..path..'/?.lua;'..path..'/?/init.lua'
end

function system.add_cpath(path)
	package.path = package.cpath..';'..path..'/?.so'
end

return system
