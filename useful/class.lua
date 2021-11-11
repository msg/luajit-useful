--
-- u s e f u l / c l a s s . l u a
--
local class = { }

function class.Class(...)
	local class = { } -- luacheck: ignore

	class._class	= class
	class.__index	= class

	local bases = {...}
	for i, base in ipairs(bases) do
		for k, v in pairs(base) do
			-- all members of class implementation (last entry) used
			if i == #bases then
				class[k] = v
			-- __index ignored for base classes
			-- it will have to be called or set specifically
			elseif k ~= '__index' then
				class[k] = v
			end
		end
	end

	class._is_a = { [class] = true }
	for _, base in ipairs(bases) do
		if base._is_a ~= nil then
			for c in pairs(base._is_a) do
				class._is_a[c] = true
			end
		end
		class._is_a[base] = true
	end

	function class:is_a(def)
		return self._is_a[def]
	end

	setmetatable(class, {
		__call = function (class, ...) -- luacheck: ignore
			local instance = setmetatable({ }, class)
			-- run the new method if it's there
			if class.__gc ~= nil then
				instance._gc = newproxy(true)
				local mt = getmetatable(instance._gc)
				mt.__gc = function()
					class.__gc(instance)
				end
			end
			if class.new then
				class.new(instance, ...)
			end
			return instance
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

