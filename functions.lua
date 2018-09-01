--
-- u s e f u l / f u n c t i o n s . l u a
--

-- vim:ft=lua
module(..., package.seeall)

function callable(obj)
	return type(obj) == 'function' or getmetatable(obj) and
			getmetatable(obj).__call
end

function memoize()
	return setmetatable({ }, {
		__index = function(self, key, ...)
			self[key] = func(key, ...)
			return self[key]
		end,
		__call = function(self, key) return self[key] end
	})
end

function lambda(func)
	local code = 'return function(a,b,c) return ' .. func .. ' end'
	local chunk = assert(loadstring(code, 'tmp'))
	return chunk()
end

local lambdas = memoize()

function function_arg(func)
	if type(func) == 'string' then
		func = lambdas(func)
	else
		assert(callable(func), 'expecting function or callable object')
	end
	return func
end

function bind1(func, a)
	func = function_arg(func)
	return function(...)
		return func(a, ...)
	end
end

function bind2(func, b)
	func = function_arg(func)
	return function(a, ...)
		return func(a, b, ...)
	end
end

function compose(func1, func2)
	func1 = function_arg(func1)
	func2 = function_arg(func2)
	return function(...)
		return func1(func2(...))
	end
end

function take2(func)
	func = function_arg(func)
	return function(...)
		local _,value = func(...)
		return value
	end
end

