--
-- u s e f u l / p a t h . l u a
--
local path = { }

local ffi	= require('ffi')
local  C	=  ffi.C

local strings	= require('useful.strings')

ffi.cdef([[
	char *dirname(char *path);
	char *basename(char *path);
	char *realpath(char *path, char *resolved);
]])

function path.readpath(path) -- luacheck: ignore path
	local f = io.open(path,'r')
	local d = f:read('*a')
	f:close()
	return d
end

function path.writepath(path, buf) -- luacheck: ignore path
	local f = io.open(path,'wb')
	f:write(buf)
	f:close()
	return #buf
end
path.putfile = path.writepath -- backward compatibility

function path.abspath(path) -- luacheck: ignore path
	if path ~= '' then
		local buf = ffi.new('char[4096]')
		local p = ffi.new('char[?]', #path+1, path)
		C.realpath(p, buf)
		return ffi.string(buf);
	else
		return path
	end
end

function path.dirpath(path) -- luacheck: ignore path
	if path ~= '' then
		local p = ffi.new('char[?]', #path+1, path)
		return ffi.string(C.dirname(p))
	else
		return path
	end
end

function path.basepath(path) -- luacheck: ignore path
	if path ~= '' then
		local p = ffi.new('char[?]', #path+1, path)
		return ffi.string(C.basename(p))
	else
		return path
	end
end

local function split_last(path, sep) -- luacheck: ignore path
	local entries = strings.split(path, '%'..sep)
	local last = table.remove(entries, #entries)
	return strings.join(entries, sep), last
end

local directory_sep = package.config:sub(1,1)
path.directory_sep = directory_sep

local function split_path(path) -- luacheck: ignore path
	return split_last(path, directory_sep)
end
path.split_path = split_path
path.dir_path = split_path

function path.split_ext(path) -- luacheck: ignore path
	return split_last(path, '.')
end

function path.base_path(path) -- luacheck: ignore path
	return select(2, split_path(path))
end

function path.join(...)
	return table.concat({...}, directory_sep)
end

return path
