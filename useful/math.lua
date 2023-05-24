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

useful_math.round = function(x)
	return math.floor(x + 0.5)
end

return useful_math
