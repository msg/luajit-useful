--
-- u s e f u l / i o m e m . l u a
--

local iomem = { }

local  max		=  math.max
local  min		=  math.min
local  concat		=  table.concat
local  insert		=  table.insert

local class		= require('useful.class')
local  Class		=  class.Class
			  require('useful.compatible')
local  unpack		=  table.unpack			-- luacheck:ignore

local WriteIO = Class({
	new = function(self)
		self.data = { }
	end,

	close = function() end,
	flush = function() end,
	setvbuf = function() end,

	seek = function(self, whence, offset)
		local s = concat(self.data)
		offset = offset or 0
		if whence == 'set' then
			s = s:sub(1, offset)
		elseif whence == 'cur' or whence == 'end' then
			s = s:sub(1, #s + offset)
		end
		self.data = { s }
		return #s
	end,

	lines = function()
		error('only write operations on WriteIO')
	end,

	read = function()
		error('only write operations on WriteIO')
	end,

	write = function(self, ...)
		for _,v in ipairs({...}) do
			insert(self.data, tostring(v))
		end
	end,

	__tostring = function(self)
		return concat(self.data)
	end,
})
iomem.WriteIO = WriteIO

local ReadIO = Class({
	new = function(self, str)
		self.pos = 1
		self.str = str
	end,

	close = function() end,
	flush = function() end,
	setvbuf = function() end,

	seek = function(self, whence, offset)
		local pos = self.pos
		if whence == 'set' then
			pos = offset or pos
		elseif whence == 'cur' then
			pos = pos + (offset or 0)
		elseif whence == 'end' then
			pos = #self.str + (offset or 0)
		end
		pos = max(1, min(#self.str, pos))
		self.pos = pos
		return pos
	end,

	lines = function(self)
		return function()
			return self:read('*l')
		end
	end,

	read = function(self, ...)
		local str = self.str
		local pos = self.pos
		local args = {...}
		local results = { }
		if #args < 1 then
			insert(args, '*l')
		end
		for i,arg in ipairs(args) do
			if arg == '*l' then
				local l = str:find('\n', pos) or #str + 1
				arg = str:sub(pos, l - 1)
				if pos < #str + 1 then
					insert(results, arg)
				end
				pos = l + 1
			elseif arg == '*a' then
				insert(results, str:sub(pos))
				pos = #str + 1
				break
			elseif type(arg) == 'number' then
				if pos <= #str then
					insert(results, str:sub(pos, pos + arg - 1))
				end
				pos = min(pos + arg, #str + 1)
			else
				error('invalid format arg #'..i)
			end
		end
		self.pos = pos
		return unpack(results)
	end,

	write = function()
		error('only read operations on ReadIO')
	end,
})
iomem.ReadIO = ReadIO

iomem.iomem = function(str)
	if str == nil then
		return WriteIO()
	else
		return ReadIO(str)
	end
end

return iomem
