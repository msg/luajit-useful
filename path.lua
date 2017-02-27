
module(..., package.seeall)

local ffi	= require('ffi')
local strings	= require('useful.strings')
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

local sep = package.config:sub(1,1)

function split_path(path)
	local dentries = strings.split(path, sep)
	local base = table.remove(dentries, #dentries)
	return strings.join(dentries, sep), base
end

function split_ext(path)
	local entries = strings.split(path, '%.', 1)
	entries[#entries] = '.' .. entries[#entries]
	return entries
end

function base_path(path)
	local path, base = split_path(path)
	return base
end

function dir_path(path)
	local path, base = split_path(path)
	return path
end
