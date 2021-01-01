--
-- u s e f u l / p o i n t e r s . l u a
--
local pointers = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  cast	=  ffi.cast
local  gc	=  ffi.gc
local  fstring	=  ffi.string
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof

local bit	= require('bit')
local  tohex	=  bit.tohex

		  require('posix.stdlib')

local stdio	= require('useful.stdio')
local  sprintf	=  stdio.sprintf

local pointer_size = sizeof('void *')
ffi.cdef(sprintf([[
	typedef union { char bytes[%d]; void *voidp; } pointer ;
]], pointer_size))

function pointers.pointer_to_string(p)
	local np = new('pointer')
	np.voidp = cast('void *', p)
	return fstring(np.bytes, pointer_size)
end

function pointers.string_to_pointer(s, type)
	local np = new('pointer')
	np.bytes = s:sub(1, pointer_size)
	return cast(type or 'void *', np.voidp)
end

function pointers.pointer_to_hex(p)
	return '0x'..tohex(cast('int64_t', cast('void *', p)))..'LL'
end

function pointers.hex_to_pointer(hex, type)
	return cast(type or 'void *', assert(load('return '..hex))())
end

function pointers.new(type, size)
	local p = C.malloc(size or sizeof(type))
	return gc(cast(type..'*', p), function() C.free(p) end)
end

return pointers
