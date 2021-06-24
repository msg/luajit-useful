--
-- u s e f u l / s t a t e m a c h i n e . l u a
--
local statemachine = { }

local class	= require('useful.class')
local  Class	=  class.Class
local system	= require('useful.system')
local  is_main	=  system.is_main

local function make_stop_states(...)
	local states = {...}
	local stop_states = {}
	if #states < 1 then
		states = { 'done' }
	end
	for _,state in pairs(states) do
		stop_states[state] = true
	end
	return stop_states
end

local StateMachine = Class({
	new = function(self, init_state)
		self.init_state		= init_state or 'done'
		self.state		= init_state or 'done'
		self.states		= {}
		self:add_state('done', self.done)
	end,

	get_state = function(self)
		return self.state
	end,

	set_state = function(self, state_table)
		self.state = state_table.state
	end,

	add_state = function(self, name, func)
		self.states[name] = func
	end,

	-- done is a stop state "always"
	done = function(self) -- luacheck: ignore
		return 'done'
	end,

	-- restart at the initial state
	restart = function(self)
		self.state = self.init_state
	end,

	-- run one "step" of current state
	step = function(self)
		if self.states[self.state] == nil then
			if self.state == nil then
				error('state == nil', 2)
			else
				error(string.format('invalid state %s', self.state), 2)
			end
		end
		local state = self.states[self.state](self)
		if state ~= nil then
			self.state = state
		end
	end,

	-- run until the "next" state change or stop state (including 'done')
	next = function(self, ...)
		local stop_states = make_stop_states(...)
		local state = self.state
		while state == self.state and
		      stop_states[self.state] == nil do
			self:step()
		end
		return self.state
	end,

	-- "run" the state machine until the stop states reached
	-- the stop state is called once at the end.
	run = function(self, ...)
		local stop_states = make_stop_states(...)
		while stop_states[self.state] == nil do
			self:step()
		end
		self:step() -- call stop state once
	end,
})
statemachine.StateMachine = StateMachine

local function main()
end

if is_main() then
	main()
else
	return statemachine
end

