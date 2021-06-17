--
-- u s e f u l / m m a l l o c . l u a
--
local mmalloc = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local bit	= require('bit')
local  band	=  bit.band
local  bnot	=  bit.bnot
local  bor	=  bit.bor
local  lshift	=  bit.lshift

local sys_mman	= require('posix.sys.mman')

function mmalloc.align(sz)
	local mask = bnot(lshift(bnot(0ULL), 12))
	return band(sz + mask - 1, bnot(mask))
end

function mmalloc.mfree(p, sz)
	local msz = mmalloc.align(sz)
	C.munmap(p, msz)
end

function mmalloc.mmalloc(sz, no_gc)
	local prot	= bor(C.PROT_READ, C.PROT_WRITE)
	local map	= bor(C.MAP_PRIVATE, C.MAP_ANONYMOUS)
	local msz	= mmalloc.align(sz)
	local p		= C.mmap(nil, msz, prot, map, -1, 0)
	if p == sys_mman.MAP_FAILED then
		return ffi.cast('void *', nil)
	else
		if no_gc == true then
			return p
		else
			return ffi.gc(p, function() mmalloc.mfree(p, sz) end)
		end
	end
end

return mmalloc
