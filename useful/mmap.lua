--
-- u t i l / m m a p . l u a
--
local mmap	= { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  gc		=  ffi.gc

local bit		= require('bit')
local  bor		=  bit.bor

		  require('posix.fcntl')
		  require('posix.unistd')
		  require('posix.sys.mman')

local class	= require('useful.class')
local  Class	=  class.Class

mmap.MMAP = Class({
	new = function(self, path, addr, size, options)
		options = options or {
			mode = 'read',
		}
		self.path = path
		self.addr = cast('off_t', addr)
		self.size = cast('size_t', size)

		local prot  = C.PROT_READ
		local flags = bor(C.O_RDONLY, C.O_SYNC)
		if     options.mode == 'write' then
			prot	= C.PROT_WRITE
			flags	= bor(C.O_WRONLY, C.O_SYNC)
		elseif options.mode == 'read_write' then
			prot	= bor(C.PROT_READ, C.PROT_WRITE)
			flags	= bor(C.O_RDWR, C.O_SYNC)
		end
		self.fd = C.open(path, flags)
		if self.fd < 0 then
			self.p = nil
			return
		end

		self.p = C.mmap(nil, self.size, prot,
				C.MAP_SHARED, self.fd, addr)
		if self.p == C.MAP_FAILED then
			C.close(self.fd)
			self.p = nil
			self.fd = -1
		else
			self.p = cast('char *', self.p)
			-- cleanup code
			self.p = gc(self.p, function() self:__gc() end)
		end
	end,

	close = function(self)
		if self.p ~= nil then
			C.munmap(self.p, self.size)
		end
		self.p = nil
		if self.fd > -1 then
			C.close(self.fd)
		end
		self.fd = -1
	end,

	__gc = function(self) -- tables don't call this metamethod
		self:close()
	end,
})

return mmap
