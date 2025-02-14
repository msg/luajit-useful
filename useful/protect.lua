--
-- u s e f u l / p r o t e c t . l u a
--
local protect = { }

		  require('posix.string')

		  require('useful.compatible')
local  pack	=  table.pack				-- luacheck:ignore
local  unpack	=  table.unpack				-- luacheck:ignore
local system		= require('useful.system')
local  errno_string_	=  system.errno_string

local function pack_ok(ok, ...)
	return ok, pack(...)
end
protect.pack_ok = pack_ok

protect.default_error	= error
protect.traceback_error	= function(message, level)
	error(message..'\n'..debug.traceback(), level)
end
protect.error		= protect.default_error

-- throw : throw pcall like return as error
local throw = function(ok, err, ...)
	if not ok then
		protect.error(err, 2) -- non-localized so it can be changed
	else
		return err, ...
	end
end
protect.throw = throw

-- throw1: throw pcall like return but use first parameter on good return
local throw1 = function(v, err, ...)
	if not v then
		protect.error(err, 2) -- non-localized so it can be changed
	else
		return v, err, ... -- NOTE: difference from throw above
	end
end
protect.throw1 = throw1

-- unprotect : unprotect call using throw semantics
protect.unprotect = function(func)
	assert(type(func) == 'function')
	return function(...)
		return throw(func(...))
	end
end

-- unprotect : unprotect call using throw1 semantics
protect.unprotect1 = function(func)
	assert(type(func) == 'function')
	return function(...)
		return throw1(func(...))
	end
end

-- protect : protect call and return values from function on lua stack
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

-- protect1 : protect call and return values from call in table
protect.protect1 = function(func)
	assert(type(func) == 'function')
	return function(...)
		local ok, args = pack_ok(pcall(func, ...))
		if ok then
			return args -- NOTE: difference from protect above
		else
			return nil, args[1]
		end
	end
end

local default_errno_string = errno_string_
protect.errno_string = default_errno_string

-- protect_s : protect C library call with int like return
protect.protect_s = function(func, errno_string)
	assert(type(func) == 'function')
	errno_string = errno_string or default_errno_string
	return function(...)
		local rc, args = pack_ok(func(...))
		if rc < 0 then
			return nil, errno_string()
		else
			return rc, unpack(args)
		end
	end
end

return protect
