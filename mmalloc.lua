module(..., package.seeall)

local ffi	= require('ffi')
local sys_mman	= require('posix.sys.mman')
local bit	= require('bit')

local bnot, bor, band = bit.bnot, bit.bor, bit.band
local lshift, rshift = bit.lshift, bit.rshift

local C = ffi.C

function align(sz)
	local mask = bnot(lshift(bnot(0), 12))
	return band(sz + mask - 1, bnot(mask))
end

function mmalloc(sz)
	local prot = bor(sys_mman.PROT_READ, sys_mman.PROT_WRITE)
	local map = bor(sys_mman.MAP_PRIVATE, sys_mman.MAP_ANONYMOUS)
	local p = C.mmap(nil, align(sz), prot, map, 0, 0)
	if p == sys_mman.MAP_FAILED then
		return ffi.cast('void *', nil)
	end
	return p
end

function mfree(p, sz)
	return C.munmap(p, align(sz))
end

