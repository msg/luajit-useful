--
-- u s e f u l / p o i n t e r s . l u a
--
local pointers = { }

local ffi	= require('ffi')
local bit	= require('bit')

local sprintf	= require('useful.stdio').sprintf

local pointer_size = ffi.sizeof('void *')
ffi.cdef(sprintf([[
	typedef union { char bytes[%d]; void *voidp; } pointer ;
]], pointer_size))

function pointers.pointer_to_string(p)
	local np = ffi.new('pointer')
	np.voidp = ffi.cast('void *', p)
	return ffi.string(np.bytes, pointer_size)
end

function pointers.string_to_pointer(s)
	local np = ffi.new('pointer')
	np.bytes = s:sub(1, pointer_size)
	return ffi.new('void *', np.voidp)
end

function pointers.pointer_to_hex(p)
	local np = ffi.new('pointer')
	np.voidp = p
	local s = '0x'
	for i=0,pointer_size do
		s = s .. string.format('%02x', bit.band(np.bytes[i], 0xff))
	end
	return s
end

return pointers
