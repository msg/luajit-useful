--
-- s c h e d u l e r / i n i t . l u a
--

--[[
This file is heavily based on https://mode13h.io/coroutines-scheduler-in-lua/.
It was modified and cleaned up.  The current priority scheme cannot work
because sorting a non-array table which is how pool is stored doesn't work.
During `step()`, all ready threads are collected into an array.  That is the
one that needs to be sorted.

Copyright (c) 2015 by Marco Lizza (marco.lizza@gmail.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]]--

local scheduler = {}

local  co_create	=  coroutine.create
local  co_resume	=  coroutine.resume
local  co_running	=  coroutine.running
local  co_status	=  coroutine.status
local  co_yield		=  coroutine.yield

local  insert		=  table.insert

local class		= require('useful.class')
local  Class		=  class.Class
			  require('useful.compatible')
local  pack		=  table.pack			-- luacheck:ignore
local  unpack		=  table.unpack			-- luacheck:ignore
local functional	= require('useful.functional')
local  bind1		=  functional.bind1
local time_		= require('useful.time')
local  now		=  time_.now
local  time_dt		=  time_.dt

local READY	= 0	scheduler.READY		= READY
local RUNNING	= 1	scheduler.RUNNING	= RUNNING
local WAITING	= 2	scheduler.WAITING	= WAITING
local SLEEPING	= 3	scheduler.SLEEPING	= SLEEPING
local CHECKING	= 4	scheduler.CHECKING	= CHECKING
local EXIT	= 5	scheduler.EXIT		= EXIT

local Thread = Class({
	new = function(self, scheduler_, thread, args)
		self.scheduler	= scheduler_
		self.thread	= thread
		self.args	= args
		self.priority	= 50
		self.resumes	= 0
		self.error	= self.default_error
		self:set(READY)
		self.scheduler:add(self)
	end,

	set = function(self, state, value, time)
		self.state	= state
		self.value	= value
		self.time	= time
	end,

	default_error = function(results, thread)	--luacheck:ignore
		print('thread error:\n'..tostring(results))
		io.stdout:flush()
	end,

	status = function(self)
		return co_status(self.thread)
	end,

	ready = function(self, dt)
		local status = self:status()
		if status == "dead" then
			self.scheduler:remove(self)
			return false
		elseif status ~= "suspended" then
			return false
		elseif self.state == EXIT then
			self.scheduler:remove(self)
			return false
		elseif self.state == SLEEPING then
			self.time = self.time - dt
			if self.time <= 0 then
				self.state = READY
			end
		elseif self.state == CHECKING then
			if self.value() then
				self.state = READY
				self.value = nil
			end
		elseif self.state == WAITING then
			if self.time ~= nil then
				self.time = self.time - dt
				if self.time <= 0 then
					self.state = READY
					self.time = nil
					-- self.value == nil when signaled
				end
			end
		end
		return self.state == READY
	end,

	resume = function(self)
		local function pack_ok(ok, ...)
			local a = {...}
			if not ok then
				a[1] = a[1]..': '..debug.traceback(self.thread)
			end
			return ok, a
		end
		self.resumes = self.resumes + 1
		return pack_ok(co_resume(self.thread, unpack(self.args)))
	end,

	yield = function(self, ...)
		return self.scheduler:yield(...)
	end,

	sleep = function(self, ...)
		return self.scheduler:sleep(...)
	end,

	check = function(self, ...)
		return self.scheduler:check(...)
	end,

	wait = function(self, ...)
		return self.scheduler:wait(...)
	end,

	timed_wait = function(self, ...)
		return self.scheduler:timed_wait(...)
	end,

	signal = function(self, ...)
		return self.scheduler:signal(...)
	end,

})

local Scheduler = Class({
	new = function(self)
		self.threads	= { }
		self.self	= co_running()
	end,

	thread = function(self)
		return self.threads[co_running()]
	end,

	set = function(self, ...)
		local thread = co_running()
		assert(thread ~= self.self, 'cannot call set on main thread')
		self.threads[thread]:set(...)
	end,

	add = function(self, thread)
		self.threads[thread.thread] = thread
	end,

	remove = function(self, thread)
		self.threads[thread.thread] = nil
	end,

	yield = function(self, ...)
		self:set(READY, nil)
		return co_yield(...)
	end,

	sleep = function(self, time, ...)
		assert(type(time) == 'number')
		self:set(SLEEPING, nil, time)
		return co_yield(...)
	end,

	check = function(self, predicate, ...)
		assert(type(predicate) == 'function')
		self:set(CHECKING, predicate)
		return co_yield(...)
	end,

	wait = function(self, id, ...)
		assert(type(id) ~= 'function')
		self:set(WAITING, id)
		return co_yield(...)
	end,

	timed_wait = function(self, id, time, ...)
		assert(type(id) ~= 'function')
		assert(type(time) == 'number')
		self:set(WAITING, id, time)
		return co_yield(...)
	end,

	signal = function(self, id)
		for _,thread in pairs(self.threads) do
			if thread.state == WAITING and thread.value == id then
				thread.state = READY
				thread.value = nil
			end
		end
	end,

	spawn = function(self, procedure, ...)
		local thread	= co_create(procedure)
		local state	= Thread(self, thread, pack(...), READY)
		return state
	end,

	stop = function(self, thread_)
		local thread	= self.threads[thread_]
		thread.state	= EXIT
	end,

	collect_ready = function(self, dt)
		local ready	= {}
		for _,thread in pairs(self.threads) do
			if thread:ready(dt) then
				insert(ready, thread)
			end
		end
		table.sort(ready, function(a, b)
			return a.priority < b.priority
		end)
		return ready
	end,

	resume_ready = function(self, ready)	--luacheck:ignore
		for _,thread in ipairs(ready) do
			-- some other thread stopped this one?
			if thread.state ~= EXIT then
				thread.state	= RUNNING
				local ok, ret = thread:resume()
				if not ok then
					thread.error(ret[1])
				else
					thread.args = ret or { n=0 }
				end
			end
		end
	end,

	step = function(self)
		local current	= now()
		local dt	= time_dt(current, self.last or current)
		self.last	= current

		local ready	= self:collect_ready(dt)
		self:resume_ready(ready)
	end,

	has_threads = function(self)
		return next(self.threads) ~= nil
	end,

	run = function(self)
		while self:has_threads() do
			self:step()
		end
	end,

	make_bind = function(self, env)
		env.check	= bind1(self.check, self)
		env.signal	= bind1(self.signal, self)
		env.sleep	= bind1(self.sleep, self)
		env.spawn	= bind1(self.spawn, self)
		env.thread	= bind1(self.thread, self)
		env.step	= bind1(self.step, self)
		env.stop	= bind1(self.stop, self)
		env.timed_wait	= bind1(self.timed_wait, self)
		env.yield	= bind1(self.yield, self)
		env.has_threads	= bind1(self.has_threads, self)
		env.scheduler	= self
		env.run		= function()
			while env.has_threads() do
				env.step()
			end
		end
	end,
})
scheduler.Scheduler = Scheduler

local main_scheduler	= Scheduler()
main_scheduler:make_bind(scheduler)

return scheduler
