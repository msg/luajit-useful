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

local class		= require('useful.class')
local  Class		=  class.Class

local function align_to_page(addr)
	return cast('char *', band(cast('off_t', addr), bnot(0xfff)))
end
mmap.align_to_page = align_to_page

mmap.MMAP = Class({
	new = function(self, path, addr, size, options)
		options = options or {
			prot		= C.PROT_READ,
			open_flags	= C.O_RDONLY,
			flags		= C.MAP_SHARED,
		}
		self.path	= path
		self.addr	= align_to_page(addr)
		local offset	= addr - self.addr
		self.size	= cast('size_t', size + offset)

		self.fd = C.open(path, options.open_flags)
		if self.fd < 0 then
			self.p = nil
			return
		end
		self.base	= C.mmap(self.addr, self.size, options.prot,
					options.flags, self.fd, offset)
		if self.base == C.MAP_FAILED then
			C.close(self.fd)
			self.base	= nil
			self.p		= nil
			self.fd		= -1
		else
			self.base	= cast('char *', self.base)
			self.p		= self.base + offset
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
