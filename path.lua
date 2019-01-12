--
-- u s e f u l / p a t h . l u a
--
local path = { }

local ffi	= require('ffi')
local strings	= require('useful.strings')
local C		= ffi.C

ffi.cdef([[
	char *dirname(char *path);
	char *basename(char *path);
	char *realpath(char *path, char *resolved);
]])

function path.readpath(path)
	return io.open(path,'r'):read('a*')
end

function path.putfile(path, buf)
	local f = io.open(path,'wb')
	f:write(buf)
	f:close()
	return #buf
end

function path.abspath(path)
	if path ~= '' then
		local buf = ffi.new('char[4096]')
		local p = ffi.new('char[?]', #path, path)
		C.realpath(p, buf)
		return ffi.string(buf);
	else
		return path
	end
end

function path.dirpath(path)
	if path ~= '' then
		local p = ffi.new('char[?]', #path, path)
		return ffi.string(C.dirname(p))
	else
		return path
	end
end

function path.basepath(path)
	if path ~= '' then
		local p = ffi.new('char[?]', #path, path)
		return ffi.string(C.basename(p))
	else
		return path
	end
end

local function split_last(path, sep)
	local entries = strings.split(_path, sep)
	local last = table.remove(entries, #dentries)
	return strings.join(entries, sep), last
end

local directory_sep = package.config:sub(1,1)

local function split_path(path)
	return split_last(path, directory_sep)
end

path.split_path = split_path

function path.split_ext(path)
	return split_last(path, '.')
end

function path.base_path(path)
	return split_path(path)[2]
end

function path.dir_path(path)
	return split_path(path)[1]
end

return path
