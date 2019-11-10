--
-- u s e f u l / m m a l l o c . l u a
--
local mmalloc = { }

local ffi	= require('ffi')
local sys_mman	= require('posix.sys.mman')
local bit	= require('bit')

local bnot, bor, band = bit.bnot, bit.bor, bit.band
local lshift = bit.lshift

local C = ffi.C

function mmalloc.align(sz)
	local mask = bnot(lshift(bnot(0), 12))
	return band(sz + mask - 1, bnot(mask))
end

function mmalloc.mmalloc(sz)
	local prot	= bor(sys_mman.PROT_READ, sys_mman.PROT_WRITE)
	local map	= bor(sys_mman.MAP_PRIVATE, sys_mman.MAP_ANONYMOUS)
	local msz	= mmalloc.align(sz)
	local p		= C.mmap(nil, msz, prot, map, 0, 0)
	if p == sys_mman.MAP_FAILED then
		return ffi.cast('void *', nil)
	else
		return ffi.gc(p, function() C.munmap(p, msz) end)
	end
	return p
end

return mmalloc
