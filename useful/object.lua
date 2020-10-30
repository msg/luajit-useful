--
-- u s e f u l / o b j e c t . l u a
--
--
local object = {}

local class	= require('useful.class')
local  Class	=  class.Class
local system	= require('useful.system')
local  is_main	=  system.is_main

function object.is_object(o)
	return type(o) == 'table' and o._class ~= nil
end

function object.verify_type(v, _type)
	if type(v) == _type then
		return true
	else
		return false, 'not a ' .. type(v)
	end
end

function object.verify_class(v, class) -- luacheck:ignore
	if object.is_object(v) and v:is_a(class) then
		return true
	else
		return false, 'not the correct object'
	end
end

function object.verify_function(value)
	local _type = type(value)
	if _type == "table" and value._class ~= nil then
		return function(v)
			return object.verify_class(v, value._class)
		end
	else
		return function(v)
			return object.verify_type(v, _type)
		end
	end
end

local declarations_mt = {
	__newindex = function(self, key, value)
		self:add_member(key, value, self._access)
	end,
	__index = function(self, key)
		return self._members[key].value
	end,
}

-- make custom ObjectClass to wrap Class
-- - to callmethed before and after :new(...)
-- - setup members and access
local ObjectClass = function(...)
	local object_class = Class(...)

	local new = function(class, ...) -- luacheck:ignore
		local instance = { _class=class }
		-- run the new method if it's there

		instance._members = {}
		instance._r = {}
		instance._w = {}

		-- all classes will have functions and they should be 'r'
		-- initialize only once?
		for name,value in pairs(class) do
			if name ~= '__index' then
				instance._members[name] = { value=value }
				instance._r[name] = true
			end
		end
		setmetatable(instance, class)
		instance:declarations('rw')
		if class.new then
			class.new(instance, ...)
		end
		instance:_finish()
		return instance
	end

	setmetatable(object_class, {
		__call = new,
	})
	return object_class
end
object.ObjectClass = ObjectClass

local StrongClass = ObjectClass({
	declarations = function(self, access)
		rawset(self, '_access', access or 'rw')
		setmetatable(self, declarations_mt)
	end,

	_finish = function(self)
		self._access = nil
		self._class.__newindex = function(tbl, key, value)
			local member = tbl._members[key]
			if member == nil then
				error('no member "'..key..'"', 2)
			elseif tbl._w[key] == nil then
				error('readonly member "'..key..'"', 2)
			end

			if member.verify then
				local valid, msg = member.verify(value)
				if not valid then
					error(msg..' for member "'..key..'"', 2)
				end
			end
			member.value = value
		end

		self._class.__index = function(tbl, key)
			local member = tbl._members[key]
			if member == nil then
				error('no member "' .. key .. '"', 2)
			elseif tbl._r[key] == nil then
				error('writeonly member "' .. key .. '"', 2)
			end
			return member.value
		end

		setmetatable(self, self._class)

		return self
	end,

	verification = function(self, key, verify)
		local members = rawget(self, '_members')
		members[key].verify = verify
	end,

	add_member = function(self, key, value, access, verify)
		local member = { value=value, verify=verify }
		if verify == nil then
			member.verify = object.verify_function(value)
		end
		self._members[key] = member
		if access:find('r') then self._r[key] = true end
		if access:find('w') then self._w[key] = true end
	end,

	remove_member = function(self, key)
		self._members[key] = nil
		self._r[key] = nil
		self._w[key] = nil
	end,
})

object.StrongClass = function(...)
	return ObjectClass(StrongClass, ...)
end

local WeakClass = ObjectClass({
	-- all the StrongClass members become empty
	declarations	= function(self, access) end, -- luacheck: ignore
	verification	= function(self, key, verify) end, -- luacheck: ignore
	_finish		= function(self) end, -- luacheck: ignore
	add_member	= function(self, key, value, access) -- luacheck: ignore
		self[key] = value
	end,
	remove_member	= function(self, key)
		self[key] = nil
	end,
})

object.WeakClass = function(...)
	return ObjectClass(WeakClass, ...)
end

local function main()
	--local Class = object.WeakClass
	local OClass = object.StrongClass
	local O = OClass({
		new = function(self)
			self.next = self

			self.ii = 6
			self.ss = 'a string'

			self:declarations('r')
			self.i = 5
			self.t = { 1, 2, 3 }
			self.s = "a string"
		end,

		method = function(self, ...) -- luacheck: ignore self
			local args = { ... }
			print('method:')
			for i,arg in ipairs(args) do
				print('', i, arg)
			end
		end,
	})

	local function get_member(o, member)
		print('get_member', member)
		return o[member]
	end

	local function set_member(o, member, value)
		print('set_member', member, value)
		o[member] = value
	end

	print("o = O()")
	local o = O()
	print('is_a(O)', o:is_a(O))
	print('is_a(StrongClass)', o:is_a(StrongClass))
	print('is_a(WeakClass)', o:is_a(WeakClass))
	print("p = O()")
	local p = O()
	print('', pcall(get_member, o, 'next'))
	print('', pcall(get_member, o, 'i'))
	print('', pcall(get_member, o, 'ii'))
	print('', pcall(get_member, o, 'ss'))
	print('', pcall(get_member, o, 'zz'))
	print('', pcall(set_member, o, 'next', p))
	print('', pcall(set_member, o, 'next', 5))
	print('', pcall(set_member, o, 'next', 'a string'))
	print('', pcall(set_member, o, 'i', 5))
	print('', pcall(set_member, o, 'i', 'a string'))
	print('', pcall(set_member, o, 'ii', 5))
	print('', pcall(set_member, o, 'ii', 'a string'))
	print('', pcall(set_member, o, 'ss', 5))
	print('', pcall(set_member, o, 'ss', 'a string'))
	print('', pcall(set_member, o, 'zz', 'a new member'))
	print('', pcall(set_member, o, 'method', 'try to change method'))
	o:method('a', 'b', 1, 2, 3)
end

if is_main() then
	main()
else
	return object
end
