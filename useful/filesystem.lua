--
-- u s e f u l / f i l e s y s t e m . l u a
--
local filesystem = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local bit	= require('bit')
local  band	=  bit.band

		  require('posix.dirent')
		  require('posix.errno')
local stat	= require('posix.sys.stat')
		  require('posix.string')
		  require('posix.unistd')

local path	= require('useful.path')
local system	= require('useful.system')
local  unpack	=  system.unpack

local function strerror(errno)
	return ffi.string(C.strerror(errno or ffi.errno()))
end

local function convert_permissions(st)
	local all_permissions = 'xwr'--'rwxrwxrwx'
	local permissions = ''
	for i=0,8 do
		if band(st.st_mode, bit.lshift(1,i)) ~= 0 then
			local flag = all_permissions:sub((i%3)+1,(i%3)+1)
			permissions = flag..permissions
		else
			permissions = '-'..permissions
		end
	end
	return permissions
end

local attribute_modes = {
	[C.S_IFDIR] = 'directory',
	[C.S_IFCHR] = 'char device',
	[C.S_IFBLK] = 'block device',
	[C.S_IFREG] = 'file',
	[C.S_IFLNK] = 'link',
	[C.S_IFSOCK] = 'socket',
}

local function convert_mode(st)
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
	mode		= convert_mode,
	permissions	= convert_permissions,
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

filesystem.attributes = function(filepath, arg, stat_func)
	local st = ffi.new('struct stat')
	local rc = (stat_func or stat.stat)(filepath, st)
	if rc < 0 then
		error(strerror())
	end
	return stat_to_attributes(st, arg)
end

filesystem.symlinkattributes = function(filepath, arg)
	local result = { filesystem.attributes(filepath, arg, stat.lstat) }
	if result[1] ~= nil then
		local buf = ffi.new('char[4096]')
		local rc = C.readlink(filepath, buf, 4096)
		if rc > -1 then
			result[1].target = ffi.string(buf)
		end
	end
	return unpack(result)
end

filesystem.exists = function(path) -- luacheck:ignore
	return pcall(filesystem.attributes, path, 'mode')
end

local function is_mode(path, what_mode) -- luacheck:ignore
	local ok, mode = filesystem.exists(path)
	if not ok then
		return false
	else
		return mode == what_mode
	end
end

filesystem.is_block_device = function(path) -- luacheck:ignore
	return is_mode(path, 'block device')
end

filesystem.is_char_device = function(path) -- luacheck:ignore
	return is_mode(path, 'char device')
end

filesystem.is_directory = function(path) -- luacheck:ignore
	return is_mode(path, 'directory')
end

filesystem.is_file = function(path) -- luacheck:ignore
	return is_mode(path, 'file')
end

local dir_iter = function(state)
	state.ent = C.readdir(state.dir)
	if state.ent == nil then
		C.closedir(state.dir)
		state.dir = nil
		return nil
	end
	return ffi.string(state.ent.d_name)
end

filesystem.dir = function(path) -- luacheck:ignore
	local state = {
		dir = C.opendir(path),
		ent = nil,
	}
	if state.dir == nil then
		error(strerror())
	end
	state.dir = ffi.gc(state.dir, function()
		if state.dir ~= nil then
			C.closedir(state.dir)
		end
	end)
	return dir_iter, state
end

filesystem.list = function(path) -- luacheck:ignore
	local list = { }
	for name in filesystem.dir(path) do
		if name ~= '.' and name ~= '..' then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

filesystem.chdir = function(path) -- luacheck:ignore
	local rc = C.chdir(path)
	if rc < 0 then
		error(strerror())
	end
	return rc
end

filesystem.currentdir = function()
	local buf = ffi.new('char[4096]')
	local rc = C.getcwd(buf, 4096)
	if rc < 0 then
		error(strerror())
	end
	return rc
end

filesystem.link = function(old, new, symlink)
	local rc
	if symlink == true then
		rc = C.symlink(old, new)
	else
		rc = C.link(old, new)
	end
	if rc < 0 then
		error(strerror())
	end
	return rc
end

filesystem.mkdir = function(dirname, permissions)
	local rc = C.mkdir(dirname, permissions or tonumber(0755, 8))
	if rc < 0 then
		error(strerror())
	end
	return rc
end

filesystem.rmdir = function(dirname)
	local rc = C.rmdir(dirname)
	if rc < 0 then
		error(strerror())
	end
	return rc
end

filesystem.mkdirp = function(_path, permissions)
	permissions = permissions or tonumber(0755, 8)
	local dir = path.split_path(_path)
	while not filesystem.exists(dir) do
		local rc = filesystem.mkdirp(dir, permissions)
		if rc < 0 and ffi.errno() ~= C.EEXIST then
			return rc
		end
	end
	if not filesystem.exists(_path) then
		return C.mkdir(_path, permissions)
	else
		return 0
	end
end

local ftw
ftw = function(path, func) -- luacheck:ignore
	local attributes = filesystem.symlinkattributes
	for entry in filesystem.dir(path) do
		if entry ~= '.' and entry ~= '..' then
			local entry_path = path .. '/' .. entry
			local entry_stat = { }
			local ok = pcall(attributes, entry_path, entry_stat)
			if not ok then
				entry_stat = nil
			end
			if func(entry_path, entry_stat) == false then
				return false
			end
			if not entry_stat then -- luacheck:ignore
			elseif entry_stat.mode == 'directory' then
				if ftw(entry_path, func) == false then
					return false
				end
			end
		end
	end
	return true
end
filesystem.ftw = ftw

return filesystem
