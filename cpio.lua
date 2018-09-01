#!/usr/bin/luajit
--
-- u s e f u l / c p i o . l u a
--

local function is_main()
	return debug.getinfo(4) == nil
end

if not is_main() then
	module(..., package.seeall)
end

local bit = require('bit')
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local class = require('useful.class')
local Class = class.Class

-- This is a lujit module to read/write cpio files in "New ASCII Format"
--
-- $ man 5 cpio
--
-- will describe the format.  It's going to be used for .tap logging as the
-- tarfile python object cannot generate tar files to stdout.

local insert	= table.insert
local remove	= table.remove
local sprintf	= string.format
local printf	= function(...) io.stdout:write(sprintf(...)) end

function pad4(l)
	return band(4 - band(l, 3), 3)
end

local function octal(val)
	local oct = 0
	local bit = 0
	while val > 0 do
		oct = bor(oct, lshift(math.fmod(val, 10), bit))
		bit = bit + 3
		val = math.floor(val / 10)
	end
	return oct
end

function eval(str)
	return loadstring('return ' .. str)()
end

NEW_CPIO_MAGIC	= '070701'
END_OF_ARCHIVE	= 'TRAILER!!!'

-- note TYPE_* are in octal
TYPE_MASK	= octal(0170000)
TYPE_SOCKET	= octal(0120000)
TYPE_SYMLINK	= octal(0120000)
TYPE_REGULAR	= octal(0100000)
TYPE_BLOCK	= octal(0060000)
TYPE_DIR	= octal(0040000)
TYPE_CHAR	= octal(0020000)
TYPE_FIFO	= octal(0010000)
TYPE_SUID	= octal(0004000)
TYPE_SGID	= octal(0002000)
TYPE_STICKY	= octal(0001000)

cpio_fields = { 'c_ino', 'c_mode', 'c_uid', 'c_gid',
	'c_nlink', 'c_mtime', 'c_filesize',
	'c_devmajor', 'c_devminor', 'c_rdevmajor', 'c_rdevminor',
	'c_namesize', 'c_check',
}

Header = Class({
	new = function(self, path, fields)
		-- ctor
		for _,field in ipairs(cpio_fields) do
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
		if data:sub(1,6) ~= NEW_CPIO_MAGIC then
			error('bad magic not ' .. NEW_CPIO_MAGIC)
		end
		for i,field in ipairs(cpio_fields) do
			local offset = 7 + (i-1) * 8
			self[field] = eval('0x' .. data:sub(offset, offset+7))
		end
	end,

	read = function(self, file)
		header_len = 6 + 8 * #cpio_fields
		self:parse(file:read(header_len))
		self.path = file:read(self.c_namesize)
		file:read(pad4(header_len + #self.path))
		self.path = self.path:sub(1, self.c_namesize - 1)
	end,

	format = function(self)
		self.c_namesize = #self.path + 1
		local chunks = { NEW_CPIO_MAGIC }
		for _,field in ipairs(cpio_fields) do
			insert(chunks, sprintf('%08x', self[field]))
		end
		local s = table.concat(chunks) .. self.path .. '\0'
		return s .. string.rep('\0', pad4(#s))
	end,
})

CPIO = Class({
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
		local header = Header(path, {
			c_mode		= mode,
			c_filesize	= #data,
			c_ino		= self.ino
		})
		header:update(fields)
		self:write(header:format())
		self:write(data)
		self:write(string.rep('\0', pad4(#data)))
		self.ino = self.ino + 1
	end,

	write_file = function(self, path, data, mode)
		mode = mode or octal(0644)
		mode = bor(mode, TYPE_REGULAR)
		self:write_data(path, data, mode)
	end,

	write_symlink = function(self, path, data, mode)
		mode = mode or octal(0644)
		mode = bor(mode, TYPE_SYMLINK)
		self:write_data(path, data, mode)
	end,

	write_special = function(self, path, mode)
		self:write_data(path, '', mode)
	end,

	write_dir = function(self, path, mode)
		mode = mode or octal(0755)
		mode = bor(mode, TYPE_DIR)
		self:write_special(path, mode)
	end,

	write_end_of_archive = function(self)
		header = Header(END_OF_ARCHIVE, { c_mtime = 0 })
		self:write(header:format())
	end,

	close = function(self)
		self:write_end_of_archive()
		self.file:close()
	end,

	skip = function(self, header)
		local size = header.c_filesize
		self.file:seek(size + pad4(size), 'cur')
	end,

	read = function(self, count)
		return self.file:read(count)
	end,

	read_contents = function(self, header)
		data = self:read(header.c_filesize)
		self:read(pad4(header.c_filesize))
		return data
	end,

	read_header = function(self)
		local header = Header()
		header:read(self.file)
		return header
	end,

	read_entry = function(self)
		local header = self:read_header()
		return header, self:read_contents(header)
	end,
})

local function main()
	local f = io.open('test.cpio', 'w')
	local cpio = CPIO(f)
	for i=0,99 do
		cpio:write_file(sprintf('a/b/c/d/testing/%02d', i),
				string.rep(string.char(i), 100+i))
	end
	cpio:write_end_of_archive()
	f:close()
	f = io.open('test.cpio', 'r')
	local cpio = CPIO(f)
	while true do
		local header, contents = cpio:read_entry()
		if header.path == END_OF_ARCHIVE then
			break
		end
		printf("%s:\n", header.path)
		for _,field in pairs(cpio_fields) do
			printf(" %-12s= 0x%08x\n", field, header[field])
		end
	end
	f:close()
end

if is_main() then
	main()
else
	return M
end

