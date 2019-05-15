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
	setfenv(0, env)
	env.assert		= env.assert or assert
	env.error		= env.error or error
	env.getfenv		= env.getfenv or getfenv
	env.setfenv		= env.setfenv or setfenv
	env.getmetatable	= env.getmetatable or getmetatable
	env.setmetatable	= env.setmetatable or setmetatable
	env.next		= env.next or next
	env.pcall		= env.pcall or pcall
	env.print		= env.print or print
	env.pairs		= env.pairs or pairs
	env.select		= env.select or select
	env.tonumber		= env.tonumber or tonumber
	env.tostring		= env.tostring or tostring
	env.type		= env.type or type
	env.unpack		= env.unpack or unpack
	env.xpcall		= env.xpcall or xpcall
	for _,name in ipairs({ 'math', 'table', 'coroutine', 'string' }) do
		if env[name] == nil then
			sandbox.export(env, name, getfenv()[name])
		end
	end
	if env.os == nil then
		env.os = {
			-- only allowed os calls
			clock		= os.clock,
			-- running 5.1.3 or higher:
			date		= os.date,
			time		= os.time,
			difftime	= os.difftime,
		}
	end
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

