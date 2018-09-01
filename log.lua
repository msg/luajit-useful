--
-- u s e f u l / l o g . l u a
--

-- vim:ft=lua
module(..., package.seeall)

NONE	= 0
ERROR	= 1
WARNING	= 2
INFO	= 3
DEBUG	= 4
ALL	= 5

sprintf = string.format

function Log(level)
	local self = { }
	self.level = level or ALL

	function self.write(buf) end
	function self.clear() end

	function self.message(level, fmt, ...)
		if level <= self.level then
			self.write(sprintf(fmt, ...))
		end
	end

	function self.error(fmt, ...) self.message(ERROR, fmt, ...) end
	function self.warning(fmt, ...) self.message(WARNING, fmt, ...) end
	function self.info(fmt, ...) self.message(INFO, fmt, ...) end
	function self.debug(fmt, ...) self.message(DEBUG, fmt, ...) end

	return self
end

function StringLog(level)
	local self = Log(level)
	self.data = {}

	function self.write(buf) table.insert(self.data, buf) end
	function self.clear() self.data = {} end
	function self.tostring() return table.concat(self.data, '\n') end

	return self
end

function FileLog(filename, level)
	local self = Log(level)
	self.filename = filename

	function self.write(buf)
		if self.filename == '-' then
			io.stdout:write(buf)
		else
			f = io.open(self.filename, 'a')
			f:write(buf)
			f:close()
		end
	end

	return self
end

function GroupLog(level)
	local self = Log(level)
	self.logs = {}

	function self.add_log(log)
		table.insert(self.logs, log)
	end

	function self.write(buf)
		for _,log in ipairs(self.logs) do
			log.write(buf)
		end
	end

	function self.clear()
		for _,log in ipairs(self.logs) do
			log.clear()
		end
	end

	return self
end

