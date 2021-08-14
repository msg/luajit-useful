#!/usr/bin/luajit
--
-- u s e f u l / c p i o . l u a
--
local cpio = { }

local bit		= require('bit')
local  band		=  bit.band
local  bor		=  bit.bor

local class		= require('useful.class')
local  Class		=  class.Class
local iomem		= require('useful.iomem')
local stdio		= require('useful.stdio')
local  sprintf		=  stdio.sprintf
local  printf		=  stdio.printf
local system		= require('useful.system')
local  is_main		=  system.is_main
local  loadstring	=  system.loadstring

local  insert		=  table.insert

-- This is a lujit module to read/write cpio files in "New ASCII Format"
--
-- $ man 5 cpio
--
-- will describe the format.  It's going to be used for .tap logging as the
-- tarfile python object cannot generate tar files to stdout.

function cpio.pad4(l)
	return band(4 - band(l, 3), 3)
end

local function octal(val)
	return tonumber(val, 8)
end

function cpio.eval(str)
	return loadstring('return ' .. str)()
end

cpio.NEW_CPIO_MAGIC	= '070701'
cpio.END_OF_ARCHIVE	= 'TRAILER!!!'

-- note TYPE_* are in octal
cpio.TYPE_MASK		= octal(0170000)
cpio.TYPE_SOCKET	= octal(0120000)
cpio.TYPE_SYMLINK	= octal(0120000)
cpio.TYPE_REGULAR	= octal(0100000)
cpio.TYPE_BLOCK		= octal(0060000)
cpio.TYPE_DIR		= octal(0040000)
cpio.TYPE_CHAR		= octal(0020000)
cpio.TYPE_FIFO		= octal(0010000)
cpio.TYPE_SUID		= octal(0004000)
cpio.TYPE_SGID		= octal(0002000)
cpio.TYPE_STICKY	= octal(0001000)

cpio.cpio_fields = { 'c_ino', 'c_mode', 'c_uid', 'c_gid',
	'c_nlink', 'c_mtime', 'c_filesize',
	'c_devmajor', 'c_devminor', 'c_rdevmajor', 'c_rdevminor',
	'c_namesize', 'c_check',
}

cpio.Header = Class({
	new = function(self, path, fields)
		-- ctor
		for _,field in ipairs(cpio.cpio_fields) do
			self[field] = 0
		end
		self.c_nlink = 1
		self.c_mtime = os.time()
		self.path = path or ''
		self:update(fields)

		return self
	end,

	update = function(self, fields)
		if fields == nil then
			return
		end
		for field, value in pairs(fields) do
			self[field] = value
		end
	end,

	parse = function(self, data)
		if data:sub(1,6) ~= cpio.NEW_CPIO_MAGIC then
			error('bad magic not ' .. cpio.NEW_CPIO_MAGIC)
		end
		for i,field in ipairs(cpio.cpio_fields) do
			local offset = 7 + (i-1) * 8
			self[field] = cpio.eval('0x' ..
					data:sub(offset, offset+7))
		end
	end,

	read = function(self, file)
		local header_len = 6 + 8 * #cpio.cpio_fields
		self:parse(file:read(header_len))
		self.path = file:read(self.c_namesize)
		file:read(cpio.pad4(header_len + #self.path))
		self.path = self.path:sub(1, self.c_namesize - 1)
	end,

	format = function(self)
		self.c_namesize = #self.path + 1
		local chunks = { cpio.NEW_CPIO_MAGIC }
		for _,field in ipairs(cpio.cpio_fields) do
			insert(chunks, sprintf('%08x', self[field]))
		end
		local s = table.concat(chunks) .. self.path .. '\0'
		return s .. string.rep('\0', cpio.pad4(#s))
	end,
})

cpio.CPIO = Class({
	new = function(self, file)
		self.file	= file
		self.ino	= 1
	end,

	flush = function(self)
		self.file:flush()
	end,

	write = function(self, data)
		self.file:write(data)
	end,

	write_data = function(self, path, data, mode, fields)
		local header = cpio.Header(path, {
			c_mode		= mode,
			c_filesize	= #data,
			c_ino		= self.ino
		})
		header:update(fields)
		self:write(header:format())
		self:write(data)
		self:write(string.rep('\0', cpio.pad4(#data)))
		self.ino = self.ino + 1
	end,

	write_file = function(self, path, data, mode)
		mode = mode or octal(0644)
		mode = bor(mode, cpio.TYPE_REGULAR)
		self:write_data(path, data, mode)
	end,

	write_symlink = function(self, path, data, mode)
		mode = mode or octal(0644)
		mode = bor(mode, cpio.TYPE_SYMLINK)
		self:write_data(path, data, mode)
	end,

	write_special = function(self, path, mode)
		self:write_data(path, '', mode)
	end,

	write_dir = function(self, path, mode)
		mode = mode or octal(0755)
		mode = bor(mode, cpio.TYPE_DIR)
		self:write_special(path, mode)
	end,

	write_end_of_archive = function(self)
		local header = cpio.Header(cpio.END_OF_ARCHIVE, { c_mtime = 0 })
		self:write(header:format())
	end,

	close = function(self)
		self:write_end_of_archive()
		self.file:close()
	end,

	skip = function(self, header)
		local size = header.c_filesize
		self.file:seek(size + cpio.pad4(size), 'cur')
	end,

	read = function(self, count)
		return self.file:read(count)
	end,

	read_contents = function(self, header)
		local data = self:read(header.c_filesize)
		self:read(cpio.pad4(header.c_filesize))
		return data
	end,

	read_header = function(self)
		local header = cpio.Header()
		header:read(self.file)
		return header
	end,

	read_entry = function(self)
		local header = self:read_header()
		return header, self:read_contents(header)
	end,
})

local function main()
	local f = iomem.iomem()
	local c = cpio.CPIO(f) -- luacheck: ignore cpio
	for i=0,99 do
		c:write_file(sprintf('a/b/c/d/testing/%02d', i),
				string.rep(string.char(i), 100+i))
	end
	f:close()
	c:write_end_of_archive()

	local s = tostring(f)
	f = iomem.iomem(s)
	c = cpio.CPIO(f)
	while true do
		local header, contents = c:read_entry() -- luacheck: ignore contents
		if header.path == cpio.END_OF_ARCHIVE then
			break
		end
		printf("%s:\n", header.path)
		for _,field in pairs(cpio.cpio_fields) do
			printf(" %-12s= 0x%08x\n", field, header[field])
		end
	end
	f:close()
end

if is_main() then
	main()
else
	return cpio
end

