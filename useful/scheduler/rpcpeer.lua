#!/usr/bin/luajit
--
-- s c h e d u l e r / r p c p e e r . l u a
--
local rpcpeer = { }

package.path = './?/init.lua;'..package.path

local ffi		= require('ffi')
local  C		=  ffi.C
local  errno		=  ffi.errno

			  require('posix.poll')

local class		= require('useful.class')
local  Class		=  class.Class
local scheduler		= require('useful.scheduler')
local  check		=  scheduler.check
local  exit		=  scheduler.exit
local  sleep		=  scheduler.sleep
local  spawn		=  scheduler.spawn
local  step		=  scheduler.step
local poll		= require('useful.scheduler.poll')
local  Poll		=  poll.Poll
local socket		= require('useful.scheduler.socket')
local  TCP		=  socket.TCP
local  TCP_RPC		=  socket.TCP_RPC
local time		= require('useful.time')
local  now		=  time.now

rpcpeer.RPCPeer = Class({
	new = function(self, timeout, max)
		self.timeout	= timeout or 0.05
		self.max	= max or 2
		self.poll	= Poll()
		self.current	= now()
		self.sock	= TCP()
		self.rpc	= TCP_RPC(nil, 8192, self.timeout)
	end,

	remove = function(self, sock)
		--print('remove')
		self.poll:remove(sock)
		exit()
	end,

	submit = function(self)
		while true do
			check(function() return #self.rpc.pending > 0 end)
			for _,request in ipairs(self.rpc.pending) do
				if request.msg ~= nil then
					self.rpc:send(request.msg, request.to)
					self.sock.events = C.POLLIN
					request.msg = nil
					request.to = nil
				end
			end
		end
	end,

	client = function(self, sock)
		local client_ignore = {
			[C.EAGAIN]	= true,
			[C.EWOULDBLOCK]	= true,
			[C.ETIMEDOUT]	= true,
		}
		local function client_error(sock)	--luacheck:ignore
			local err = errno()
			if not client_ignore[err] then
				self:remove(sock)
			end
		end
		self.poll:add(sock)
		sock:on_error(client_error)
		self.rpc.sock = sock
		while true do
			self.rpc:step(self.timeout)
		end
	end,

	serve = function(self)
		local serve_ignore = {
			[C.EINTR]	= true,
			[C.EAGAIN]	= true,
			[C.ETIMEDOUT]	= true,
		}
		local function serve_error()
			local err = errno()
			if serve_ignore[err] then
				return
			end
			error('serve error errno='..tostring(err))
		end

		local sock = self.sock
		--print('serve entering loop')
		sock:set_timeout(self.timeout)
		sock:on_error(serve_error)
		local id	= 1
		while true do
			if self.poll.npfds > self.max then
				sleep(self.timeout)
			else
				local client	= TCP(sock:accept(0))
				spawn(self.client, self, client, id)
				id = id + 1
			end
		end
	end,

	step = function(self)
		self.poll:poll(self.timeout)
		step()
	end,

	server = function(self, port)
		self.sock:reuseaddr()
		self.sock:bind('*', port)
		self.sock:listen(10)
		self.sock:nonblock()
		self.poll:add(self.sock)
		self.rpc.sock = self.sock
		spawn(self.serve, self)
	end,

	connect = function(self, host, port)
		local rc, msg = self.sock:connect(host, port)
		if rc ~= nil then
			self.rpc.sock = self.sock
			self.sock:nonblock()
			spawn(self.client, self, self.sock, 0)
			spawn(self.submit, self)
		end
		return rc, msg
	end,
})

return rpcpeer
