--
-- e x p r e s s / m i m e . l u a
--
local mime = { }

local function open_file(name)
	for entry in package.path:gmatch('[^;]+') do
		entry = entry:gsub('%?.*$', name)
		local f = io.open(entry)
		if f ~= nil then
			return f
		end
	end
end

local info	= debug.getinfo(open_file)
local mime_file	= info.short_src:sub(1,-5)..'.types'

local f		= open_file(mime_file)
if f == nil then
	error('http/mime.types not found')
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

