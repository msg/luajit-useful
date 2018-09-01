--
-- u s e f u l / l o g . l u a
--

-- vim:ft=lua
module(..., package.seeall)

local class = require('useful.class')
local Class = class.Class

NONE	= 0
ERROR	= 1
WARNING	= 2
INFO	= 3
DEBUG	= 4
ALL	= 5

sprintf = string.format

Log = Class({
	new = function(self, level)
		self.level = level or ALL
	end,

	write = function(self, buf)
	end,

	clear = function(self)
	end,

	message = function(self, level, fmt, ...)
		if level <= self.level then
			self.write(sprintf(fmt, ...))
		end
	end,

	error = function(self, fmt, ...)
		self:message(ERROR, fmt, ...)
	end,

	warning = function(self, fmt, ...)
		self:message(WARNING, fmt, ...)
	end,

	info = function(self, fmt, ...)
		self:message(INFO, fmt, ...)
	end,

	debug = function(self, fmt, ...)
		self:message(DEBUG, fmt, ...)
	end,
})

StringLog = Class(Log, {
	new = function(self, level)
		Log.new(self, level)
	end,

	write = function(self, buf)
		table.insert(self.data, buf)
	end,

	clear = function(self)
		self.data = {}
	end,

	tostring = function(self)
		return table.concat(self.data, '\n')
	end
})

FileLog = Class(Log, {

	new = function(self, filename, level)
		Log.new(self, level)
		self.filename = filename
	end,

	write = function(self, buf)
		if self.filename == '-' then
			io.stdout:write(buf)
		else
			f = io.open(self.filename, 'a')
			f:write(buf)
			f:close()
		end
	end,
})

GroupLog = Class(Log, {
	new = function(self, level)
		Log.new(self, level)
		self.logs = {}
	end,

	add_log = function(self, log)
		table.insert(self.logs, log)
	end,

	write = function(self, buf)
		for _,log in ipairs(self.logs) do
			log:write(buf)
		end
	end,

	clear = function(self)
		for _,log in ipairs(self.logs) do
			log:clear()
		end
	end,
})
