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
local  remove		=  table.remove
local  pack		=  table.pack			--luacheck:ignore
local  unpack		=  table.unpack			--luacheck:ignore

local time		= require('util.time')
local  now		=   time.now

local READY	= 0	scheduler.READY		= READY
local RUNNING	= 1	scheduler.RUNNING	= RUNNING
local WAITING	= 2	scheduler.WAITING	= WAITING
local SLEEPING	= 3	scheduler.SLEEPING	= SLEEPING
local CHECKING	= 4	scheduler.CHECKING	= CHECKING
local EXIT	= 5	scheduler.EXIT		= EXIT

local pool = {}
scheduler.pool	= pool

local function set_state(status, value, time)		--luacheck:ignore
	local state	= pool[co_running()]
	state.status	= status
	state.value	= value
	state.time	= time
end

scheduler.yield = function(...)
	set_state(READY, nil)
	return co_yield(...)
end

scheduler.sleep = function(time, ...)			--luacheck:ignore
	assert(type(time) == 'number')
	set_state(SLEEPING, nil, time)
	return co_yield(...)
end

scheduler.check = function(predicate, ...)
	assert(type(predicate) == 'function')
	set_state(CHECKING, predicate)
	return co_yield(...)
end

scheduler.exit = function(...)
	set_state(EXIT)
	return co_yield(...)
end

scheduler.wait = function(id, ...)
	assert(type(id) ~= 'function')
	set_state(WAITING, id)
	return co_yield(...)
end

scheduler.timed_wait = function(id, time, ...)		--luacheck:ignore
	assert(type(id) ~= 'function')
	assert(type(time) == 'number')
	set_state(WAITING, id, time)
	return co_yield(...)
end

scheduler.signal = function(id)
	for _,state in pairs(pool) do
		if state.status == WAITING and state.value == id then
			state.status = READY
			state.value = nil
		end
	end
end

scheduler.spawn = function(procedure, ...)
	local thread = co_create(procedure)
	pool[thread] = {
		args	= pack(...),		--luacheck:ignore
		status	= READY,
		value	= nil,
	}
	return thread
end

scheduler.stop = function(thread)
	local state	= pool[thread]
	state.status	= EXIT
end

local thread_ready = function(thread, state, dt)
	local status = co_status(thread)
	if status == "dead" then
		pool[thread] = nil
	elseif status == "suspended" then
		if state.status == SLEEPING then
			state.time = state.time - dt
			if state.time <= 0 then
				state.status = READY
			end
		elseif state.status == CHECKING then
			if state.value() then
				state.status = READY
				state.value = nil
			end
		elseif state.status == WAITING then
			if state.time == nil then
				state.time = state.time - dt
				if state.value.time <= 0 then
					state.status = READY
					state.time = nil
					-- state.value == nil when signaled
				end
			end
		elseif state.status == EXIT then
			pool[thread] = nil
		end
		return state.status == READY
	end
end
scheduler.thread_ready = thread_ready

local default_error_func = function(results)
	print(results[1])
end

local on_error_func = default_error_func
scheduler.on_error = function(error_func)
	on_error_func = error_func
end

local last
scheduler.step = function()
	local current	= now()
	last		= last or current
	local dt	= time.dt(current, last)
	last		= current
	local threads_to_resume = {}

	for thread,state in pairs(pool) do
		if thread_ready(thread, state, dt) then
			insert(threads_to_resume, thread)
		end
	end

	for _,thread in ipairs(threads_to_resume) do
		local state	= pool[thread]
		state.status	= RUNNING
		local results = pack(co_resume(thread, unpack(state.args)))
		if remove(results, 1) == false then
			results[1] = results[1]..'\n'..debug.traceback(thread)
			on_error_func(results)
		end
	end
end

return scheduler
