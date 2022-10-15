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

mime.exts = { }
local f = open_file('http/mime.types')
if f == nil then
	error('http/mime.types not found')
end
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

