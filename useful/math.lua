--
-- u s e f u l / m a t h . l u a
--
local useful_math = { }

local ffi	= require('ffi')
local  new	=  ffi.new

useful_math.divmod = function(x, y)
	local i64 = new('int64_t', x)
	return i64 / y, i64 % y
end

return useful_math
