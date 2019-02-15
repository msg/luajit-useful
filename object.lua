--
-- u s e f u l / o b j e c t . l u a
--
--
local object = {}

local is_main	= require('useful.system').is_main

local tables	= require('useful.tables')
local strings	= require('useful.strings')
local Class	= require('useful.class').Class

local insert = table.insert

local structure	= tables.structure
local imap	= tables.imap
local split	= strings.split

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

function object.verify_class(v, class)
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
object.ObjectClass = function(...)
	local object_class = Class(...)

	local new = function(class, ...)
		local instance = { _class=class }
		-- run the new method if it's there

		instance._members = {}
		instance._r = {}
		instance._w = {}

		-- all classes will have functions and they should be 'r'
		-- initialize only once?
		for name,value in pairs(class) do
			if name ~= '__index' then
				local member = { value=value }
				instance._members[name] = member
				instance._r[name] = true
			end
		end
		setmetatable(instance, class)
		instance:declarations('rw')
		if class.new then
			class.new(instance, ...)
		end
		instance:finish()
		return instance
	end

	setmetatable(object_class, {
		__call = new,
	})
	return object_class
end

object.StrongObject = object.ObjectClass({
	declarations = function(self, access)
		rawset(self, '_access', access or 'rw')
		setmetatable(self, declarations_mt)
	end,

	finish = function(self)
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

object.WeakObject = object.ObjectClass({
	-- all the StrongObject members become empty
	declarations	= function(self, access) end,
	verification	= function(self, key, verify) end,
	finish		= function(self) end,
	add_member	= function(self, key, value, access)
		self[key] = value
	end,
	remove_member	= function(self, key)
		self[key] = nil
	end,
})

local function main()
	--local Object = object.WeakObject
	local Object = object.StrongObject
	local O = object.ObjectClass(Object, {
		new = function(self)
			self.ii = 6
			self.ss = 'a string'

			self:declarations('r')
			self.i = 5
			self.t = { 1, 2, 3 }
			self.s = "a string"
		end,

		method = function(self, ...)
			local args = { ... }
			print('method:')
			for i,arg in ipairs(args) do
				print('', i, arg)
			end
		end,
	})

	function get_member(o, member)
		print('get_member', member)
		return o[member]
	end

	function set_member(o, member, value)
		print('set_member', member, value)
		o[member] = value
	end

	print("o = O()")
	o = O()
	print('is_a(O)', o:is_a(O))
	print('is_a(StrongObject)', o:is_a(object.StrongObject))
	print('is_a(WeakObject)', o:is_a(object.WeakObject))
	print("p = O()")
	p = O()
	print('', pcall(get_member, o, 'i'))
	print('', pcall(get_member, o, 'ii'))
	print('', pcall(get_member, o, 'ss'))
	print('', pcall(get_member, o, 'zz'))
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
