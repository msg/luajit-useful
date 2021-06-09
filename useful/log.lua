--
-- u s e f u l / l o g . l u a
--
local log = { }

local ffi	= require('ffi')

local class	= require('useful.class')
local  Class	=  class.Class
local stdio	= require('useful.stdio')
local  sprintf	=  stdio.sprintf
local socket	= require('useful.socket')

log.NONE	= 0
log.ERROR	= 1
log.WARNING	= 2
log.INFO	= 3
log.DEBUG	= 4
log.ALL		= 5

local Log = Class({
	new = function(self, log_leader, level)
		self.log_leader	= log_leader or ''
		self.level		= level or log.ALL
	end,

	write = function(self, buf) -- luacheck: ignore
	end,

	leader = function(self)
		if self.log_leader == '' then
			return ''
		end
		return os.date(self.log_leader)..' '
	end,

	clear = function(self) -- luacheck: ignore
	end,

	message = function(self, level, fmt, ...)
		if level > self.level then
			return
		end
		self:write(sprintf(fmt, ...))
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
	new = function(self, log_leader, level)
		Log.new(self, log_leader, level)
		self.data = {}
	end,

	write = function(self, buf)
		buf = self:leader()..buf
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
	new = function(self, filename, log_leader, level)
		Log.new(self, log_leader, level)
		self.filename = filename
	end,

	write = function(self, buf)
		buf = self:leader()..buf
		if self.filename == '-' then
			io.stdout:write(buf)
			io.stdout:flush()
		else
			local f = io.open(self.filename, 'a')
			f:write(buf)
			f:close()
		end
	end,
})

log.UDPLog = Class(log.Log, {
	new = function(self, host, port, log_leader, level)
		Log.new(self, log_leader, level)
		self.dest = socket.getaddrinfo(host, port)
		self.udp = socket.UDP()
	end,

	write = function(self, buf)
		buf = self:leader()..buf
		local p = ffi.new('char[?]', #buf+1, buf) -- +1 for '\0'
		self.udp:sendto(p, #buf, self.dest)
	end,
})

log.GroupLog = Class(log.Log, {
	new = function(self, log_leader, level)
		Log.new(self, log_leader, level)
		self.logs = {}
	end,

	add_log = function(self, log) -- luacheck: ignore
		table.insert(self.logs, log)
	end,

	write = function(self, buf)
		buf = self:leader()..buf
		for _,log in ipairs(self.logs) do -- luacheck: ignore
			log:write(buf)
		end
	end,

	clear = function(self)
		for _,log in ipairs(self.logs) do -- luacheck: ignore
			log:clear()
		end
	end,
})

return log
