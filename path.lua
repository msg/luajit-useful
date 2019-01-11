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

local sep = package.config:sub(1,1)

function path.split_path(_path)
	local dentries = strings.split(_path, sep)
	local base = table.remove(dentries, #dentries)
	return strings.join(dentries, sep), base
end

function path.split_ext(_path)
	local entries = strings.split(_path, '%.')
	while #entries > 2 do
		entries[1] = entries[1] .. '.' .. table.remove(entries, 2)
	end
	entries[#entries] = '.' .. entries[#entries]
	return entries
end

function path.base_path(_path)
	local base
	_path, base = path.split_path(_path)
	return base
end

function path.dir_path(_path)
	local base
	_path, base = path.split_path(_path)
	return _path
end

return path
