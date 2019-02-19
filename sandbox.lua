#!/usr/bin/luajit
--
-- u s e f u l / s a n d b o x . l u a
--
local sandbox = { }

function sandbox.export(to_table, name, from_table)
	local table = { }
	for n,v in pairs(from_table) do
		table[n] = v
	end
	to_table[name] = table
end

function sandbox.sandbox(env)
	env			= env or { }
	env.assert		= assert
	env.error		= error
	env.getmetatable	= getmetatable
	env.setmetatable	= setmetatable
	env.next		= next
	env.pcall		= pcall
	env.print		= print
	env.pairs		= pairs
	env.select		= select
	env.tonumber		= tonumber
	env.tostring		= tostring
	env.type		= type
	env.unpack		= unpack
	env.xpcall		= xpcall
	sandbox.export(env, 'math', math)
	sandbox.export(env, 'table', table)
	sandbox.export(env, 'coroutine', coroutine)
	sandbox.export(env, 'string', string)
	env.os = {
		-- only allowed os calls
		clock		= os.clock,
		-- running 5.1.3 or higher:
		date		= os.date,
		time		= os.time,
		difftime	= os.difftime,
	}
	env.string.dump		= nil
	env._G			= env
	return env
end

function sandbox.run(untrusted_code, env)
	if untrusted_code:byte(1) == 27 then
		return nil, 'binary code prohibited'
	end
	local untrusted_function, message = loadstring(untrusted_code)
	if not untrusted_function then
		return nil, message
	end
	env = env or sandbox.sandbox()
	setfenv(untrusted_function, env)
	return pcall(untrusted_function)
end

local function main(args)
	if #arg > 0 then
		assert(sandbox.run(io.open(args[1],'r'):read('*a')))
	else
		local s = [[
			print('test')
			print(pairs)
			for n,v in pairs(_G) do
				print(n,v)
			end
		]]
		--assert(loadstring(s))()
		assert(sandbox.run(s))

		local t = [[
			print(os.date('%F'))
			f=io.open(arg[0]) -- this should fail on io
			print(f:read('*a'))
			f:close()
		]]
		assert(sandbox.run(t) == false)
	end
end

local is_main = require('useful.system').is_main
if is_main() then
	main(arg)
else
	return sandbox
end

