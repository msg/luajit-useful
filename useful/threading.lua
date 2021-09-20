
-- vim: ft=lua

-- This gets sourced in to the main lua state and any created threads with
-- lua state.  It simplifies all the C stack manipulation and threading
-- problems.

-- The threading library creates an internal lua state for managing
-- the resources between all threads.

-- loaded has the module reference
local threading = { }
local threadingc = require('useful.threadingc')

local pack	= table.pack  --luacheck:ignore
if pack == nil then
	local tables = require('useful.tables')
	pack = tables.pack
end

local exec	= threadingc.exec
local lock	= threadingc.lock
local unlock	= threadingc.unlock

local function setup() -- this is run in the management thread
	if init_ ~= nil then --luacheck:ignore
		return
	end
	init_ = true --luacheck:ignore

	local min	= math.min
	local insert	= table.insert
	local pack	= table.pack  --luacheck:ignore
	if pack == nil then
		local tables = require('useful.tables')
		pack = tables.pack
	end
	local remove	= table.remove --luacheck:ignore
	local concat	= table.concat

	--
	-- global data related stuff
	--
	data	= { } --luacheck:ignore

	local path = function(args, n)
		while #args > n do
			remove(args, #args)
		end
		return concat(args, '.')
	end

	traverse_locked = function(tbl, n, except, args) --luacheck:ignore
		local i = 1
		while i <= n - except and tbl ~= nil do
			tbl = tbl[args[i]]
			i = i + 1
		end
		if tbl == nil then
			return nil, 'entry '..path(args, i)..' not found'
		else
			return tbl --  + 1
		end
	end

	-- `data` is a global table
	set_locked = function(...) --luacheck:ignore
		local args = pack(...)
		local n = args.n
		local tbl = traverse_locked(data, n, 2, args) --luacheck:ignore
		tbl[args[n-1]] = args[n]
	end

	get_locked = function(...) --luacheck:ignore
		local args = pack(...)
		return traverse_locked(data, args.n, 0, args) --luacheck:ignore
	end

	insert_locked = function(...) --luacheck:ignore
		local args = pack(...)
		local tbl = traverse_locked(data, args.n, 1, args) --luacheck:ignore
		insert(tbl, args[args.n]) -- NOTE: above
	end

	remove_locked = function(...) --luacheck:ignore
		local args = pack(...)
		local tbl = traverse_locked(data, args.n, 1, args) --luacheck:ignore
		remove(tbl, args[args.nn])
	end

	--
	-- channeel queue related stuff
	--

	local channels	= { }

	channel_locked = function(name) --luacheck:ignore
		local channel = channels[name] or { queue = { } }
		channels[name] = channel
		return channel
	end

	flush_locked = function(name) --luacheck:ignore
		channels[name] = nil
	end

	enqueue_locked = function(name, args) --luacheck:ignore
		local channel = channel_locked(name) --luacheck:ignore
		insert(channel.queue, args)
	end

	dequeue_locked = function(name, max) --luacheck:ignore
		local channel = channel_locked(name) --luacheck:ignore
		local results = { }
		local n = min(max, #channel.queue)
		for _=1,n do
			insert(results, remove(channel.queue, 1))
		end
		if #channel.queue == 0 then -- remove queue when it's empty
			flush_locked(name) --luacheck:ignore
		end
		return results
	end

	queues_locked = function() --luacheck:ignore
		local queues = {}
		for name,_ in pairs(channels) do
			insert(queues, name)
		end
		return queues
	end
end

local function pexec(code, ...)
	return pcall(exec, code, ...)
end

local run = function(code, ...)
	lock()
	if type(code) == 'string' then
		code = loadstring(code)
	end
	local result, a, b = pexec(code, ...)
	unlock()
	if result == false then
		error('run: '..tostring(a))
	end
	return a, b
end

run(setup)

local wrap = function(code)
	return function(...) return run(code, ...) end
end

-- luacheck: push ignore
threading.set		= wrap(function(...) return set_locked(...) end)
threading.get		= wrap(function(...) return get_locked(...) end)
threading.insert	= wrap(function(...) return insert_locked(...) end)
threading.remove	= wrap(function(...) return remove_locked(...) end)
threading.queues	= wrap(function(...) return queues_locked(...) end)
threading.flush		= wrap(function(...) return flush_locked(...) end)
-- luacheck: pop
threading.run		= run

local wait	= threadingc.wait
local signal	= threadingc.signal

threading.send = function(name, ...)
	lock()
	local args = pack(...)
	local ok, result = pexec(function(name, args) --luacheck:ignore
		enqueue_locked(name, args) --luacheck:ignore
	end, name, args)
	signal(name)
	unlock()
	if not ok then
		error('threading.send: '..result[1])
	end
end

threading.receive = function(name, timeout, max)
	lock()
	max = max or 1
	local ok, result = pexec(function(name) --luacheck:ignore
		return #channel_locked(name).queue --luacheck:ignore
	end, name)
	if ok == true then
		if result == 0 then
			wait(name, timeout)
		end
		ok, result = pexec(function(name, max) --luacheck:ignore
			return dequeue_locked(name, max) --luacheck:ignore
		end, name, max)
	end
	unlock()
	if not ok then
		error('threading.receive: '..result)
	end
	return result
end

threading.start		= threadingc.start
threading.exit		= threadingc.exit
threading.setname	= threadingc.setname

return threading

