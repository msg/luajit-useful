--
-- u s e f u l / f u n c t i o n a l . l u a
--
local functional = { }

local system		= require('useful.system')
local  loadstring	=  system.loadstring

function functional.callable(obj)
	return type(obj) == 'function' or getmetatable(obj) and
			getmetatable(obj).__call
end

function functional.memoize(func)
	return setmetatable({ }, {
		__index = function(self, key, ...)
			local v = func(key, ...)
			self[key] = v
			return v
		end,
		__call = function(self, key) return self[key] end
	})
end

function functional.lambda(code)
	code = 'return function(a,b,c,d,e,f,g) return ' .. code .. ' end'
	local chunk = assert(loadstring(code, 'tmp'))
	return chunk()
end

local lambdas = functional.memoize()

local function_arg = function(func)
	if type(func) == 'string' then
		func = lambdas(func)
	else
		assert(functional.callable(func),
			'expecting function or callable object')
	end
	return func
end
functional.function_arg = function_arg

function functional.bind1(func, a)
	func = function_arg(func)
	return function(...)
		return func(a, ...)
	end
end

function functional.bind2(func, b)
	func = function_arg(func)
	return function(a, ...)
		return func(a, b, ...)
	end
end

function functional.compose(...)
	local funcs = { }
	for _,func in pairs({...}) do
		table.insert(funcs, 1, function_arg(func))
	end
	return function(...)
		local v = funcs[1](...)
		for i=2,#funcs do
			v = funcs[i](v)
		end
		return v
	end
end

function functional.take2(func)
	func = function_arg(func)
	return function(...)
		local _,value = func(...)
		return value
	end
end

return functional
