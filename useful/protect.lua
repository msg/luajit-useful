--
-- u s e f u l / p r o t e c t . l u a
--
local protect = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  errno	=  ffi.errno
local  fstring	=  ffi.string

		  require('posix.string')

local system	= require('useful.system')
local  pack	=  system.pack
local  unpack	=  system.unpack

local function pack_ok(ok, ...)
	return ok, pack(...)
end
protect.pack_ok = pack_ok

protect.default_error	= error
protect.traceback_error	= function(message, level)
	error(message..'\n'..debug.traceback(), level)
end
protect.error		= protect.default_error

local try = function(ok, err, ...)
	if not ok then
		protect.error(err, 2) -- non-localized so it can be changed
	else
		return err, ...
	end
end
protect.try = try

local try1 = function(v, err)
	if not v then
		protect.error(err, 2) -- non-localized so it can be changed
	else
		return v
	end
end
protect.try1 = try1

protect.unprotect = function(func)
	assert(type(func) == 'function')
	return function(...)
		return try(func(...))
	end
end

protect.unprotect1 = function(func)
	assert(type(func) == 'function')
	return function(...)
		return try1(func(...))
	end
end

protect.protect = function(func)
	assert(type(func) == 'function')
	return function(...)
		local ok, args = pack_ok(pcall(func, ...))
		if ok then
			return unpack(args)
		else
			return nil, args[1]
		end
	end
end

protect.protect1 = function(func)
	assert(type(func) == 'function')
	return function(...)
		local ok, args = pack_ok(pcall(func, ...))
		if ok then
			return args
		else
			return nil, args[1]
		end
	end
end

local default_errno_string = function(err)
	return fstring(C.strerror(err))
end
protect.errno_string = default_errno_string

protect.protect_s = function(func, errno_string)
	assert(type(func) == 'function')
	errno_string = errno_string or default_errno_string
	return function(...)
		local rc, args = pack_ok(func(...))
		if rc < 0 then
			return nil, errno_string(errno())
		else
			return rc, unpack(args)
		end
	end
end

return protect
