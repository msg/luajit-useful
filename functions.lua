--
-- u s e f u l / f u n c t i o n s . l u a
--
local functions = { }

function functions.callable(obj)
	return type(obj) == 'function' or getmetatable(obj) and
			getmetatable(obj).__call
end

function functions.memoize(func)
	return setmetatable({ }, {
		__index = function(self, key, ...)
			local v = func(key, ...)
			self[key] = v
			return v
		end,
		__call = function(self, key) return self[key] end
	})
end

function functions.lambda(func)
	local code = 'return function(a,b,c) return ' .. func .. ' end'
	local chunk = assert(loadstring(code, 'tmp'))
	return chunk()
end

local lambdas = functions.memoize()

function functions.function_arg(func)
	if type(func) == 'string' then
		func = lambdas(func)
	else
		assert(functions.callable(func),
			'expecting function or callable object')
	end
	return func
end

function functions.bind1(func, a)
	func = functions.function_arg(func)
	return function(...)
		return func(a, ...)
	end
end

function functions.bind2(func, b)
	func = functions.function_arg(func)
	return function(a, ...)
		return func(a, b, ...)
	end
end

function functions.compose(func1, func2)
	func1 = functions.function_arg(func1)
	func2 = functions.function_arg(func2)
	return function(...)
		return func1(func2(...))
	end
end

function functions.take2(func)
	func = functions.function_arg(func)
	return function(...)
		local _,value = func(...)
		return value
	end
end

return functions
