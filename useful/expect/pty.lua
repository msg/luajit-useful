#!/usr/bin/luajit
--
-- e x p e c t / p t y . l u a
--
local pty = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  cast	=  ffi.cast
local  fstring	=  ffi.string
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof
local bit	= require('bit')

local lpty	= require('linux.pty')
		  require('posix.fcntl')
		  require('posix.stdio')
		  require('posix.stdlib')
		  require('posix.termios')
		  require('posix.unistd')

ffi.cdef [[
char **environ;
]]

local pty_execvpe = function(file, argv, envp)
	local oldp = C.environ
	C.environ = envp
	local rc = C.execvp(file, argv)
	C.environ = oldp
	return rc
end

local pty_login_tty = function(slave_fd)
	C.setsid();
	for i=0,2 do
		if i ~= slave_fd then
			C.close(i)
		end
	end

	local slave_name = C.ttyname(slave_fd)
	if slave_name == nil then
		return -1
	end
	local dummy_fd = C.open(slave_name, C.O_RDWR)
	if dummy_fd < 0 then
		return -1
	end
	C.close(dummy_fd)

	for i=0,2 do
		if i ~= slave_fd then
			if C.dup2(slave_fd, i) < 0 then
				return -1
			end
		end
	end
	if slave_fd >= 3 then
		C.close(slave_fd);
	end
	return 0
end

local pty_fork = function(master, slave, amaster)
	local pid = C.fork()
	if pid == -1 then
		C.close(master)
		C.close(slave)
		return -1
	elseif pid == 0 then -- child
		C.close(master)
		if pty_login_tty(slave) ~= 0 then
			C.perror(cast('char *', "pty_login_tty"))
			os.exit(1)
		end
		return 0
	else -- parent
		amaster[0] = master
		return pid
	end
end

pty.spawn = function(master, slave, file, args, env, cwd, cols, rows)
	local argc	= table.getn(args)
	local argv	= cast('char **', C.calloc(argc + 2, sizeof('char *')))
	argv[0]		= cast('char *', file)
	argv[argc+1]	= cast('char *', nil)
	for i=1,argc do argv[i] = cast('char *', args[i]) end

	local envc	= table.getn(env)
	local envp	= cast('char **', C.calloc(envc + 1, sizeof('char *')))
	for i=1,envc do envp[i-1] = cast('char *', env[i]) end

	local winp		= new('struct winsize[1]')
	winp[0].ws_xpixel	= 0
	winp[0].ws_ypixel	= 0
	winp[0].ws_col		= cols
	winp[0].ws_row		= rows

	local amaster		= new('int[1]')
	local pid = pty_fork(master, slave, amaster)

	if pid ~= 0 then
		C.free(argv)
		C.free(envp)
	end

	if pid == -1 then
		return nil, 'forkpty failed'
	elseif pid == 0 then
		if #cwd then
			C.chdir(cwd)
		end
		if C.setgid(C.getgid()) == -1 then
			C.perror('setgid failed')
			os.exit(1)
		end
		if C.setuid(C.getuid()) == -1 then
			C.perror('setuid failed')
			os.exit(1)
		end
		pty_execvpe(argv[0], argv, envp)

		C.perror('execvp failed')
		os.exit(1)
	end
	return master
end

pty.open = function(cols, rows)
	local winp		= new('struct winsize[1]')
	winp[0].ws_xpixel	= 0
	winp[0].ws_ypixel	= 0
	winp[0].ws_col		= cols
	winp[0].ws_row		= rows
	local master		= new('int[1]')
	local slave		= new('int[1]')
	local name		= new('char[64]')
	local rc = lpty.lib.openpty(master, slave, name, nil, winp)
	if rc < 0 then
		return nil, 'openpty failed'
	end
	return {
		master	= master[0],
		slave	= slave[0],
		name	= fstring(name),
	}
end

pty.turn_echoing_off = function()
	local tp = new('struct termios[1]')
	if C.tcgetattr(C.STDIN_FILENO, tp) < 0 then
		return nil, 'tcgetattr failed'
	end
	tp[0].c_lflag = bit.band(tp[0].c_lflag, bit.bnot(C.ECHO))
	if C.tcsetattr(C.STDIN_FIOLENO, C.TCSAFLUSH, tp) < 0 then
		return nil, 'tcsetattr failed'
	end
	return true
end

return pty
