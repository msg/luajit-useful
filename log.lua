--
-- u s e f u l / l o g . l u a
--
local log = { }

local Class = require('useful.class').Class

log.NONE	= 0
log.ERROR	= 1
log.WARNING	= 2
log.INFO	= 3
log.DEBUG	= 4
log.ALL		= 5

sprintf = string.format

local Log = Class({
	new = function(self, level)
		self.level = level or log.ALL
	end,

	write = function(self, buf)
	end,

	clear = function(self)
	end,

	message = function(self, level, fmt, ...)
		if level <= self.level then
			self:write(sprintf(fmt, ...))
		end
	end,

	error = function(self, fmt, ...)
		self:message(log.ERROR, fmt, ...)
	end,

	warning = function(self, fmt, ...)
		self:message(log.WARNING, fmt, ...)
	end,

	info = function(self, fmt, ...)
		self:message(log.INFO, fmt, ...)
	end,

	debug = function(self, fmt, ...)
		self:message(log.DEBUG, fmt, ...)
	end,
})
log.Log = Log

log.StringLog = Class(log.Log, {
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

log.FileLog = Class(log.Log, {

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

log.GroupLog = Class(log.Log, {
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

return log
