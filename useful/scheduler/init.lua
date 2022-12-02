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
local functional	= require('useful.functional')
local  bind1		=  functional.bind1
local system		= require('useful.system')
local  pack		=  system.pack
local  unpack		=  system.unpack
local time_		= require('useful.time')
local  now		=  time_.now
local  time_dt		=  time_.dt

local READY	= 0	scheduler.READY		= READY
local RUNNING	= 1	scheduler.RUNNING	= RUNNING
local WAITING	= 2	scheduler.WAITING	= WAITING
local SLEEPING	= 3	scheduler.SLEEPING	= SLEEPING
local CHECKING	= 4	scheduler.CHECKING	= CHECKING
local EXIT	= 5	scheduler.EXIT		= EXIT

local ThreadState = Class({
	new = function(self, scheduler_, thread, args, status, value, time)
		self.scheduler	= scheduler_
		self.thread	= thread
		self.args	= args
		self.error	= self.default_error
		self:set(status, value, time)
		self.scheduler:add(self)
	end,

	set = function(self, status, value, time)
		self.status	= status
		self.value	= value
		self.time	= time
	end,

	default_error = function(results, thread)	--luacheck:ignore
		print('thread traceback:\n'
		      ..results) --:gsub('^.*stack traceback:\n', ''))
	end,

	ready = function(self, dt)
		local status = co_status(self.thread)
		if status == "dead" then
			self.scheduler:remove(self)
			return false
		elseif status ~= "suspended" then
			return false
		elseif self.status == EXIT then
			self.scheduler:remove(self)
			return false
		elseif self.status == SLEEPING then
			self.time = self.time - dt
			if self.time <= 0 then
				self.status = READY
			end
		elseif self.status == CHECKING then
			if self.value() then
				self.status = READY
				self.value = nil
			end
		elseif self.status == WAITING then
			if self.time == nil then
				self.time = self.time - dt
				if self.value.time <= 0 then
					self.status = READY
					self.time = nil
					-- self.value == nil when signaled
				end
			end
		end
		return self.status == READY
	end,

	resume = function(self)
		local function pack_ok(ok, ...)
			return ok, {...}
		end
		return pack_ok(co_resume(self.thread, unpack(self.args)))
	end,
})

local Scheduler = Class({
	new = function(self)
		self.states	= { }
		self.thread	= co_running()
	end,

	state = function(self)
		return self.states[co_running()]
	end,

	set = function(self, ...)
		local thread = co_running()
		assert(thread ~= self.thread, 'cannot call set on main thread')
		self.states[thread]:set(...)
	end,

	add = function(self, state)
		self.states[state.thread] = state
	end,

	remove = function(self, state)
		self.states[state.thread] = nil
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
		for _,state in pairs(self.states) do
			if state.status == WAITING and state.value == id then
				state.status = READY
				state.value = nil
			end
		end
	end,

	spawn = function(self, procedure, ...)
		local thread	= co_create(procedure)
		local state	= ThreadState(self, thread, pack(...), READY)
		return state
	end,

	stop = function(self, thread)
		local state	= self.states[thread]
		state.status	= EXIT
	end,

	collect_runnable = function(self, dt)
		local runnable	= {}
		for _,state in pairs(self.states) do
			if state:ready(dt) then
				insert(runnable, state)
			end
		end
		return runnable
	end,

	resume_runnable = function(self, runnable)	--luacheck:ignore
		for _,state in ipairs(runnable) do
			-- some other thread stopped this one?
			if state.status ~= EXIT then
				state.status	= RUNNING
				local ok, ret = state:resume()
				if not ok then
					state.error(ret[1])
				else
					state.args = ret or { n=0 }
				end
			end
		end
	end,

	step = function(self)
		local current	= now()
		local dt	= time_dt(current, self.last or current)
		self.last	= current

		local runnable	= self:collect_runnable(dt)
		self:resume_runnable(runnable)
	end,

	run = function(self)
		while next(self.states) do
			self:step()
		end
	end,

	make_bind = function(self, t)
		local methods = {
			'check', 'signal', 'sleep', 'spawn',
			'state', 'step', 'stop', 'timed_wait', 'wait', 'yield',
		}
		for _,method in ipairs(methods) do
			t[method] = bind1(self[method], self)
		end
		t['scheduler']	= self
		t['run']	= function()
			while next(self.states) do
				t['step']() -- this function can be modified
			end
		end
	end,
})
scheduler.Scheduler = Scheduler

local main_scheduler	= Scheduler()
main_scheduler:make_bind(scheduler)

return scheduler
