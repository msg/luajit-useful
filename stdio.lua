
local stdio = { }

stdio.sprintf = string.format

stdio.fprintf = function(file, ...)
	file:write(stdio.sprintf(...))
end

stdio.printf = function(...)
	stdio.fprintf(io.stdout, ...)
end

return stdio
