--
-- u s e f u l / s t a t e m a c h i n e . l u a
--
local statemachine = { }

local is_main = require('useful.system').is_main

local Class = require('useful.class').Class

statemachine.StateMachine = Class()

function statemachine.StateMachine:new(init_state)
	self.init_state		= init_state or 'done'
	self.state		= init_state or 'done'
	self.states		= {}
	self:add_state('done', self.done)
end

function statemachine.StateMachine:get_state()
	return self.state
end

function statemachine.StateMachine:set_state(state_table)
	self.state = state_table.state
end

function statemachine.StateMachine:add_state(name, func)
	self.states[name] = func
end

-- done is stop state "always"
function statemachine.StateMachine:done()
	return 'done'
end

-- restart at the initial state
function statemachine.StateMachine:restart()
	self.state = self.init_state
end

-- run one "step" of current state
function statemachine.StateMachine:step()
	if self.state == 'done' then
		return self.state
	end
	if self.states[self.state] == nil then
		if self.state == nil then
			error('state == nil', 2)
		else
			error(string.format('invalid state %s', self.state), 2)
		end
	end
	self.state = self.states[self.state]()
	return self.state
end

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

-- run until the "next" state change or "done"
function statemachine.StateMachine:next(...)
	local stop_states = make_stop_states(...)
	local state = self.state
	while state == self.state and stop_states[self.state] == nil do
		self:step()
	end
	return self.state
end

-- "run" the state machine until the stop states reached
function statemachine.StateMachine:run(...)
	local stop_states = make_stop_states(...)
	while stop_states[self.state] == nil do
		self:step()
	end
end

local function main()
end

if is_main() then
	main()
else
	return statemachine
end

