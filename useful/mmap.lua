--
-- u t i l / m m a p . l u a
--
local mmap	= { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  gc		=  ffi.gc

local bit		= require('bit')
local  band		=  bit.band
local  bnot		=  bit.bnot
local  bor		=  bit.bor

		  require('posix.fcntl')
		  require('posix.unistd')
		  require('posix.sys.mman')

local class	= require('useful.class')
local  Class	=  class.Class

local function align_to_page(addr)
	return band(addr, bnot(0xfff))
end

mmap.MMAP = Class({
	new = function(self, path, addr, size, options)
		options = options or {
			mode = 'read',
		}
		self.path	= path
		self.addr	= cast('off_t', align_to_page(addr))
		local offset	= addr - self.addr
		self.size	= cast('size_t', size + offset)

		local prot	= C.PROT_READ
		local flags	= bor(C.O_RDONLY, C.O_SYNC)
		if options.mode == 'write' then
			prot	= C.PROT_WRITE
			flags	= bor(C.O_WRONLY, C.OSYNC)
		elseif options.mode == 'read_write' then
			prot	= bor(C.PROT_READ, C.PROT_WRITE)
			flags	= bor(C.O_RDWR, C.OSYNC)
		end
		self.fd = C.open(path, flags)
		if self.fd < 0 then
			self.p = nil
			return
		end
		self.base	= C.mmap(nil, self.size, prot,
					C.MAP_SHARED, self.fd, self.addr)
		if self.base == C.MAP_FAILED then
			C.close(self.fd)
			self.base	= nil
			self.p		= nil
			self.fd		= -1
		else
			self.base	= cast('char *', self.base)
			self.p		= self.base + offset
			-- cleanup code
			self.base	= gc(self.base, function()
				self:__gc()
			end)
		end
	end,

	close = function(self)
		self.p		= nil
		if self.base ~= nil then
			C.munmap(self.base, self.size)
		end
		self.base	= nil
		if self.fd > -1 then
			C.close(self.fd)
		end
		self.fd		= -1
	end,

	__gc = function(self) -- tables don't call this metamethod
		self:close()
	end,
})

return mmap
