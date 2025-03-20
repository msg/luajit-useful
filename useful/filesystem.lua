--
-- u s e f u l / f i l e s y s t e m . l u a
--
local filesystem = { }

local  insert		=  table.insert
local  sort		=  table.sort

local ffi		= require('ffi')
local  C		=  ffi.C
local  errno		=  ffi.errno
local  fstring		=  ffi.string
local  gc		=  ffi.gc
local  new		=  ffi.new
local bit		= require('bit')
local  band		=  bit.band
local  bor		=  bit.bor
local  lshift		=  bit.lshift

			  require('posix.dirent')
			  require('posix.errno')
local stat		= require('posix.sys.stat')
			  require('posix.string')
			  require('posix.unistd')

			  require('useful.compatible')
local  unpack		=  table.unpack			-- luacheck:ignore
local path_		= require('useful.path')
local  split_path	=  path_.split_path
local system		= require('useful.system')
local  errno_string	=  system.errno_string

local x_map = {
	[C.S_IXUSR]			= 'x',
	[C.S_ISUID]			= 'S',
	[bor(C.S_IXUSR,C.S_ISUID)]	= 's',
	[C.S_IXGRP]			= 'x',
	[C.S_ISGID]			= 'S',
	[bor(C.S_IXGRP,C.S_ISGID)]	= 's',
	[C.S_IXOTH]			= 'x',
	[bor(C.S_IXOTH,C.S_ISVTX)]	= 't',
	[C.S_ISVTX]			= 'T',
}
local function to_permissions(st)
	return	(band(st.st_mode, C.S_IRUSR) ~= 0 and 'r' or '-') ..
		(band(st.st_mode, C.S_IWUSR) ~= 0 and 'w' or '-') ..
		(x_map[band(st.st_mode, bor(C.S_IXUSR, C.S_ISUID))] or '-') ..
		(band(st.st_mode, C.S_IRGRP) ~= 0 and 'r' or '-') ..
		(band(st.st_mode, C.S_IWGRP) ~= 0 and 'w' or '-') ..
		(x_map[band(st.st_mode, bor(C.S_IXGRP, C.S_ISGID))] or '-') ..
		(band(st.st_mode, C.S_IROTH) ~= 0 and 'r' or '-') ..
		(band(st.st_mode, C.S_IWOTH) ~= 0 and 'w' or '-') ..
		(x_map[band(st.st_mode, bor(C.S_IXOTH, C.S_ISVTX))] or '-')
end
filesystem.to_permissions = to_permissions

local function from_permissions(permissions)
	local function sub(i) return permissions:sub(i, i) end
	return bor(
		sub(1) == 'r' and C.S_IRUSR or 0,
		sub(2) == 'w' and C.S_IWUSR or 0,
		sub(3) == 'x' and C.S_IXUSR or 0,
		sub(3) == 's' and bor(C.S_ISUID, C.S_IXUSR) or 0,
		sub(3) == 'S' and C.S_ISUID or 0,
		sub(4) == 'r' and C.S_IRGRP or 0,
		sub(5) == 'w' and C.S_IWGRP or 0,
		sub(6) == 'x' and C.S_IXGRP or 0,
		sub(6) == 's' and bor(C.S_ISGID, C.S_IXGRP) or 0,
		sub(6) == 'S' and C.S_ISGID or 0,
		sub(7) == 'r' and C.S_IROTH or 0,
		sub(8) == 'w' and C.S_IWOTH or 0,
		sub(9) == 'x' and C.S_IXOTH or 0,
		sub(9) == 't' and bor(C.S_ISVTX, C.S_IXOTH) or 0,
		sub(9) == 'T' and C.S_ISVTX or 0
	)
end
filesystem.from_permissions = from_permissions

local attribute_modes = {
	[C.S_IFDIR] = 'directory',
	[C.S_IFCHR] = 'char device',
	[C.S_IFBLK] = 'block device',
	[C.S_IFREG] = 'file',
	[C.S_IFLNK] = 'link',
	[C.S_IFSOCK] = 'socket',
}

local function to_mode(st)
	return attribute_modes[band(st.st_mode, C.S_IFMT)]
end

local function make_convert(name)
	return function(st)
		return tonumber(st['st_'..name])
	end
end

local function make_convert_time(name)
	return function(st)
		return tonumber(st[name].tv_sec) +
		       tonumber(st[name].tv_nsec) * 1e-9
	end
end

local attribute_convert = {
	dev		= make_convert('dev'),
	ino		= make_convert('ino'),
	nlink		= make_convert('nlink'),
	uid		= make_convert('uid'),
	gid		= make_convert('gid'),
	rdev		= make_convert('rdev'),
	size		= make_convert('size'),
	blksize		= make_convert('blksize'),
	blocks		= make_convert('blocks'),
	mode		= to_mode,
	permissions	= to_permissions,
	modification	= make_convert_time('st_mtim'),
	access		= make_convert_time('st_atim'),
	change		= make_convert_time('st_ctim'),
}

local stat_to_attributes = function(st, arg)
	local attributes = { }
	if type(arg) == 'table' then
		attributes = arg
	elseif type(arg) == 'string' then
		return attribute_convert[arg](st)
	end

	for name,func in pairs(attribute_convert) do
		attributes[name] = func(st)
	end
	return attributes
end
filesystem.stat_to_attributes = stat_to_attributes

local attributes = function(filepath, arg, stat_func)
	local st = new('struct stat')
	local rc = (stat_func or stat.stat)(filepath, st)
	if rc < 0 then
		return nil, errno_string()
	end
	return stat_to_attributes(st, arg)
end
filesystem.attributes = attributes

local symlink_target = function(path)
	local buf = new('char[4096]')
	local rc = C.readlink(path, buf, 4096)
	if rc > -1 then
		return fstring(buf, rc)
	end
end
filesystem.symlink_target = symlink_target

filesystem.symlinkattributes = function(filepath, arg)
	local result = { attributes(filepath, arg, stat.lstat) }
	if result[1] ~= nil then
		result[1].target = symlink_target(filepath)
	end
	return unpack(result)
end

filesystem.set_permissions = function(path, permissions)
	local mode = from_permissions(permissions)
	return C.chmod(path, mode)
end

filesystem.exists = function(path)
	return attributes(path, 'mode') ~= nil
end

local function is_mode(path, what_mode)
	local mode = attributes(path, 'mode')
	if mode == nil then
		return false
	else
		return mode == what_mode
	end
end

filesystem.is_block_device = function(path)
	return is_mode(path, 'block device')
end

filesystem.is_char_device = function(path)
	return is_mode(path, 'char device')
end

filesystem.is_directory = function(path)
	return is_mode(path, 'directory')
end

filesystem.is_link = function(path)
	return is_mode(path, 'link')
end

filesystem.is_file = function(path)
	return is_mode(path, 'file')
end

local dir_iter = function(state)
	state.ent = C.readdir(state.dir)
	if state.ent == nil then
		C.closedir(state.dir)
		state.dir = nil
		return nil
	end
	return fstring(state.ent.d_name)
end

filesystem.dir = function(path)
	local state = {
		dir = C.opendir(path),
		ent = nil,
	}
	if state.dir == nil then
		error(errno_string())
	end
	state.dir = gc(state.dir, function()
		if state.dir ~= nil then
			C.closedir(state.dir)
		end
	end)
	return dir_iter, state
end

filesystem.list = function(path)
	local list = { }
	assert(path ~= nil)
	for name in filesystem.dir(path) do
		if name ~= '.' and name ~= '..' then
			insert(list, name)
		end
	end
	sort(list)
	return list
end

filesystem.chdir = function(path)
	local rc = C.chdir(path)
	if rc < 0 then
		error(errno_string())
	end
	return rc
end

filesystem.currentdir = function()
	local buf = new('char[4096]')
	local rc = C.getcwd(buf, 4096)
	if rc == nil then
		error(errno_string())
	end
	return fstring(rc)
end

filesystem.link = function(old, new_, symlink)
	local rc
	if symlink == true then
		rc = C.symlink(old, new_)
	else
		rc = C.link(old, new_)
	end
	if rc < 0 then
		error(errno_string())
	end
	return rc
end

filesystem.mkdir = function(dirname, permissions)
	local rc = C.mkdir(dirname, permissions or tonumber(0755, 8))
	if rc < 0 then
		error(errno_string())
	end
	return rc
end

filesystem.rmdir = function(dirname)
	local rc = C.rmdir(dirname)
	if rc < 0 then
		error(errno_string())
	end
	return rc
end

filesystem.mkdirp = function(path, permissions)
	permissions = permissions or tonumber(0755, 8)
	local dir = split_path(path)
	while dir ~= '' and not filesystem.exists(dir) do
		local rc = filesystem.mkdirp(dir, permissions)
		if rc < 0 and errno() ~= C.EEXIST then
			return rc
		end
	end
	if not filesystem.exists(path) then
		return C.mkdir(path, permissions)
	else
		return 0
	end
end

local ftw
ftw = function(path, func, attributes_)
	attributes_ = attributes_ or filesystem.symlinkattributes
	for entry in filesystem.dir(path) do
		if entry ~= '.' and entry ~= '..' then
			local entry_path = path .. '/' .. entry
			local entry_attrs = { }
			local ok = pcall(attributes_, entry_path, entry_attrs)
			if not ok then
				entry_attrs = nil
			end
			if func(entry_path, entry_attrs) == false then
				return false
			end
			if not entry_attrs then -- luacheck:ignore
			elseif entry_attrs.mode == 'directory' then
				if ftw(entry_path, func, attributes_) == false then
					return false
				end
			end
		end
	end
	return true
end
filesystem.ftw = ftw

return filesystem
