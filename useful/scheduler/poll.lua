--
-- s c h e d u l e r / p o l l . l u a
--
local poll = { }

local ffi		= require('ffi')
local  C		=  ffi.C
local  new		=  ffi.new

			  require('posix.errno')
			  require('posix.poll')

local class		= require('useful.class')
local  Class		=  class.Class
local scheduler		= require('useful.scheduler')
local  Scheduler	=  scheduler.Scheduler
local time		= require('useful.time')
local  now		=  time.now

local Poll = Class({
	new = function(self, max)
		max		= max or 32
		self.max	= max
		self.npfds	= 0
		self.fd_objects	= { }
		self:resize(max)
	end,

	__len = function(self)
		return self.npfds
	end,

	resize = function(self, new_size)
		assert(new_size >= self.npfds, 'size less then used')
		local new_pfds = new('struct pollfd[?]', new_size)
		for i=0,self.npfds-1 do
			new_pfds[i] = self.pfds[i]
		end
		self.pfds	= new_pfds
		self.max	= new_size
		return new_size
	end,

	add = function(self, fd_object)
		assert(self.npfds < self.max)
		self.fd_objects[self.npfds]	= fd_object
		fd_object.pfd			= self.pfds + self.npfds
		self.pfds[self.npfds].fd	= fd_object.fd
		self.npfds			= self.npfds + 1
	end,

	remove = function(self, fd_object)
		local pfds			= self.pfds
		local i				= fd_object.pfd - self.pfds
		assert(pfds[i].fd == fd_object.fd)
		self.npfds			= self.npfds - 1
		if self.npfds == 0 or self.npfds == i then
			return
		end
		-- swap removed pollfd with last pollfd
		local nfd_object		= self.fd_objects[self.npfds]
		self.fd_objects[self.npfds]	= nil
		self.fd_objects[i]		= nfd_object
		nfd_object.pfd			= pfds + i

		pfds[i].fd			= pfds[self.npfds].fd
		pfds[i].events			= pfds[self.npfds].events
	end,

	poll = function(self, timeout)
		return C.poll(self.pfds, self.npfds, timeout * 1000)
	end,
})
poll.Poll = Poll

local PollScheduler = Class(Scheduler, {
	new = function(self, timeout, max)
		Scheduler.new(self)
		self.timeout	= timeout or 0.1
		self.max	= max or 32
		self.poll	= Poll(self.max)
		self.current	= now()
	end,

	__len = function(self)
		return #self.poll
	end,

	resize = function(self, new_size)
		self.poll:resize(new_size)
	end,

	step = function(self)
		self.n = self.poll:poll(self.timeout)
		Scheduler.step(self)
	end,
})
poll.PollScheduler = PollScheduler

local poll_scheduler	= PollScheduler()
poll_scheduler:make_bind(poll)
poll.scheduler		= poll_scheduler

return poll
