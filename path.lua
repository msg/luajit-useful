
module(..., package.seeall)

local ffi	= require('ffi')
local time	= require('posix.time')
local pstring	= require('posix.string')
local C		= ffi.C

ffi.cdef([[
	char *dirname(char *path);
	char *basename(char *path);
	char *realpath(char *path, char *resolved);
]])

function readpath(path)
	return io.open(path,'r'):read('a*')
end

function putfile(path, buf)
	local f = io.open(path,'wb')
	f:write(buf)
	f:close()
	return #buf
end

function abspath(path)
	if path ~= '' then
		local buf = ffi.new('char[4096]')
		local p = ffi.new('char[?]', #path, path)
		C.realpath(p, buf)
		return ffi.string(buf);
	else
		return path
	end
end

function dirpath(path)
	if path ~= '' then
		local p = ffi.new('char[?]', #path, path)
		return ffi.string(C.dirname(p))
	else
		return path
	end
end

function basepath(path)
	if path ~= '' then
		local p = ffi.new('char[?]', #path, path)
		return ffi.string(C.basename(p))
	else
		return path
	end
end

