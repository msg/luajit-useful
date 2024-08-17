--
-- e x p r e s s / m i m e . l u a
--
local mime = { }

local info	= debug.getinfo(function() end)
local mime_file	= info.short_src:sub(1,-5)..'.types'

local f		= io.open(mime_file)
if f == nil then
	error(mime_file..' not found')
end
mime.exts	= { }
for line in f:lines() do
	local match = line:gmatch('%S+')
	local type = match()
	local ext = match()
	while ext do
		mime.exts[ext] = type
		ext = match()
	end
end

return mime

