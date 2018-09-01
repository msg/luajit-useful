--
-- c l a s s . l u a
--

local function is_main()
	return debug.getinfo(4) == nil
end

if not is_main() then
	module(..., package.seeall)
end

function Class(...)
	local class = { }

	local bases = {...}
	for i, base in ipairs(bases) do
		for k, v in pairs(base) do
			class[k] = v
		end
	end

	class._is_a = { [class] = true }
	for i, base in ipairs(bases) do
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

	class.__index = class

	setmetatable(class, {
		__call = function (class, ...)
			local instance = setmetatable({}, class)
			-- run the new method if it's there
			if instance.new then
				instance:new(...)
			end
			return instance
		end
	})

	return class
end

local function main()
	X = Class({
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
	Y = Class(X, {
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
	x = X()
	x:print()
	x:print_is()
	Y.print_is(x)
	y = Y()
	y:print()
	y:print_is()
end

if is_main() then
	main()
end

