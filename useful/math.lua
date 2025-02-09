--
-- u s e f u l / m a t h . l u a
--
local useful_math = { }

local  floor		=  math.floor

useful_math.divmod = function(x, y)
	x = x + 0LL
	y = y + 0LL
	return tonumber(x / y), tonumber(x % y)
end

useful_math.round = function(x)
	return floor(x + 0.5)
end

return useful_math
