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

local function to_permissions(st)
	local all_permissions = 'xwr'--'rwxrwxrwx'
	local permissions = ''
	for i=0,8 do
		if band(st.st_mode, lshift(1,i)) ~= 0 then
			local flag = all_permissions:sub((i%3)+1,(i%3)+1)
			permissions = flag..permissions
		else
			permissions = '-'..permissions
		end
	end
	return permissions
end

local function from_permissions(permissions)
	local mode = 0
	for i=0,8 do
		if permissions:sub(9-i,9-i) ~= '-' then
			mode = bor(mode, lshift(1, i))
		end
	end
	return mode
end

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

filesystem.symlinkattributes = function(filepath, arg)
	local result = { attributes(filepath, arg, stat.lstat) }
	if result[1] ~= nil then
		local buf = new('char[4096]')
		local rc = C.readlink(filepath, buf, 4096)
		if rc > -1 then
			result[1].target = fstring(buf)
		end
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
ftw = function(path, func)
	local attributes_ = filesystem.symlinkattributes
	for entry in filesystem.dir(path) do
		if entry ~= '.' and entry ~= '..' then
			local entry_path = path .. '/' .. entry
			local entry_stat = { }
			local ok = pcall(attributes_, entry_path, entry_stat)
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
