--
-- u s e f u l / c o m m a n d . l u a
--
local command = { }

local  sprintf	=  string.format

local system	= require('useful.system')
local  is_main	=  system.is_main
local  unpack	=  system.unpack

command.Command = function(commands, name, params, description, func)
	local self = {
		commands	= commands,
		name		= name,
		params		= params,
		description	= description,
		func		= func,
	}
	return self
end

local function clean_line(line)
	line = line:gsub('#.*$', '')
	line = line:gsub('^%s*', '')
	line = line:gsub('%s*$', '')
	return  line
end

local function wrap_lines(s, maxlen)
	maxlen = maxlen or 80
	local lines = { }
	local line = ''
	for word in s:gmatch('%S+') do
		if #line + #word + 1 > maxlen then
			table.insert(lines, line)
			line = word
		else
			line = line .. ' ' .. word
		end
	end
	table.insert(lines, line)
	return lines
end

local function make_params(names, start)
	local params = { }
	start = start or 1
	for i=start,#names do
		local name = names[i]
		table.insert(params, sprintf('<%s>', name))
	end
	return table.concat(params, ' ')
end

function command.cmd_script(command, file) -- luacheck:ignore
	local lines = { }
	for line in io.open(file):lines() do
		table.insert(lines, clean_line(line))
	end
	return command.commands.process(table.concat(lines, ' '))
end

function command.cmd_help(command) -- luacheck:ignore
	local log = command.log
	local commands = command.commands
	log('usage: %s [commands]*\n', commands.progname)
	log('  commands:\n')
	for _,command in ipairs(commands.command_list) do -- luacheck:ignore
		local sep = ''
		if #command.params > 0 then
			sep = ' '
		end
		local params = make_params(command.params)
		local usage = sprintf('%s%s%s:', command.name, sep, params)
		local desc = wrap_lines(command.description, 80-30)
		if #usage < 25 then
			log('    %-25s %s\n', usage, table.remove(desc, 1))
		else
			log('    %-25s\n', usage)
			log('    %25s %s\n', '', table.remove(desc, 1))
		end
		while #desc > 0 do
			log('    %-25s %s\n', '', table.remove(desc, 1))
		end
	end
	log('\n  multiple commands are executed consecutively\n')
	return 0
end

command.Commands = function(log)
	local self = {
		log		= log,
		commands	= { },
		command_list	= { },
		verbose		= false,
	}

	function self.quiet()
		self.verbose = false
	end

	function self.verbose()
		self.verbose = true
	end

	function self.add_command(name, params, description, func)
		local c = command.Command(self, name, params, description, func)
		c.log	= self.log
		self.commands[name] = c
		table.insert(self.command_list, c)
	end

	function self.run(name, args)
		local error = -1

		if self.commands[name] == nil then
			log('error: bad command "%s"\n', name)
			return error
		end

		local command = self.commands[name] -- luacheck:ignore
		if #args < #command.params then
			local params = make_params(command.params, #args+1)
			log('error: %s missing %s\n', name, params)
			return error
		end

		if self.verbose == true then
			local params = { }
			for i=1,#command.params do
				table.insert(params, args[i])
			end
			log('%s %s\n', name, table.concat(params, ' '))
		end

		error = command.func(command, unpack(args))
		if error < 0 then
			log('usage: %s %s\n', name, make_params(command.params))
		end

		for _=1,#command.params do
			table.remove(args, 1)
		end

		if self.verbose == true then
			log('\n')
		end

		return error
	end

	function self.process(args)
		local error = -1
		while #args > 0 do
			local name = table.remove(args, 1)
			error = self.run(name, args)
			if error < 0 then
				break
			end
		end
		return error
	end

	function self.main(args)
		self.progname = args[0]
		if #args == 0 then
			self.process({'help'})
		end
		local rc = self.process(args)
		if rc < 0 then
			self.log('use "help" command to see command list.\n')
		end
		return rc
	end

	self.add_command('help', { }, 'display list of commands',
			command.cmd_help)
	self.add_command('script', {'file'}, 'execute command from <file>',
			command.cmd_script)

	return self
end

local function main(args)
	local function printf(...)
		io.stdout:write(sprintf(...))
	end
	return command.Commands(printf).main(args)
end

if is_main() then
	main()
else
	return command
end
