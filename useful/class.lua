--
-- u s e f u l / c l a s s . l u a
--
local class = { }

function class.Class(...)
	local class = { } -- luacheck: ignore

	-- class._is_a will be overwritten below, build it locally
	local _is_a	= { [class] = true }

	local bases = {...}
	for _, base in ipairs(bases) do
		for k, v in pairs(base) do
			class[k] = v
		end
		_is_a[base] = true
		if base._is_a ~= nil then
			for class_ in pairs(base._is_a) do
				_is_a[class_] = true
			end
		end
	end
	class.__index	= class -- maybe overridden by base(s) above
	class._is_a	= _is_a	-- set it after all bases parsed

	function class:is_a(class_)
		return self._is_a[class_]
	end

	-- NOTE: if __newindex is overridden, setting it will be called in
	-- new() on each self.<name> = <value> and,
	-- rawset(self, <name>, <value>) must be used.
	--
	-- there were 2 design options:
	--
	-- 1. allow methods to be called in new()
	-- 2. allow __newindex to handle self.
	--
	-- I chose option 1 as __newindex is less often used.
	setmetatable(class, {
		__call = function (class, ...) -- luacheck: ignore
			local obj = { _class = class, _gc = newproxy(true), }
			getmetatable(obj._gc).__gc = function()
				(rawget(obj,'__gc') or
				 class.__gc or
				 function() end)(obj)
			end
			setmetatable(obj, class):new(...)
			return obj
		end
	})

	return class
end

local function main()
	local Class = class.Class

	local X = Class({
		new = function(self)
			self.x = 5
		end,
		print = function(self)
			print('x='..self.x)
		end,
	})
	function X:print_is()
		print('is_a(X)=' .. tostring(self:is_a(X)))
	end
	local Y = Class(X, {
		new = function(self)
			X.new(self)
			self.y = 4
		end,
		print = function(self)
			print('(' .. self.x .. ',' .. self.y .. ')')
		end,
	})
	function Y:print_is()
		X.print_is(self)
		print('is_a(Y)=' .. tostring(self:is_a(Y)))
	end
	local x = X()
	x:print()
	x:print_is()
	Y.print_is(x)
	local y = Y()
	y:print()
	y:print_is()
end

local system = require('useful.system')
if system.is_main() then
	main()
else
	return class
end

