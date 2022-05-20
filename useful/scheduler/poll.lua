--
-- s c h e d u l e r / p o l l . l u a
--
local poll = { }

local ffi	= require('ffi')
local  C	=  ffi.C
local  errno	=  ffi.errno
local  new	=  ffi.new

		  require('posix.poll')

local class	= require('useful.class')
local  Class	=  class.Class

poll.Poll = Class({
	new = function(self, npfds)
		npfds = npfds or 32
		self.pfds	= new('struct pollfd[?]', npfds)
		self.npfds	= 0
	end,

	add = function(self, sock)
		local npfds		= self.npfds
		self.pfds[npfds].fd	= sock.fd
		self.npfds		= npfds + 1
		sock.pfd		= self.pfds + npfds
	end,

	remove = function(self, sock)
		local npfds = self.npfds - 1
		for i=0,npfds do
			if self.pfds[i].fd == sock.fd then
				self.pfds[i].events	= 0
				self.pfds[npfds]	= self.pfds[i]
				self.npfds		= self.npfds - 1
				return
			end
		end
	end,

	poll = function(self, timeout)
		local rc = C.poll(self.pfds, self.npfds, timeout * 1000)
		if rc <= 0 then
			errno(C.EAGAIN)
		end
		return rc
	end,
})

return poll
