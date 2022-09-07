#!/usr/bin/env luajit
--
-- u s e f u l / r p c / i n i t . l u a
--
local rpc = { }

local  insert		=  table.insert
local  remove		=  table.remove

local class		= require('useful.class')
local  Class		=  class.Class
local system		= require('useful.system')
local  pack		=  system.pack
local  unpack		=  system.unpack

--
-- { type, id, method_error, args_result }
-- type: 0=request, 1=response, 2=notify
-- id: user defined
-- method_error: request,notify=method, response=error
--   method: string method name
--   error:  nil or string error (lua stack trace)
-- args_result:  request,notify=method, response=result
--   args:   array of arguments
--   result: array of arguments (nil, on error)
--

local function removen(argn, i)
	local item = remove(argn, i)
	argn.n = argn.n - 1
	return item
end
rpc.removen = removen

local function unpackn(args)
	return unpack(args, 1, args.n)
end
rpc.unpackn = unpackn

-- packing 1 to 10 arguments
--   this is required because arguments can be nil
local packs = { }
packs[0] = function() return pack() end
for i=1,10 do
	local s = 'return function(t) return table.pack('
	for j=1,i do
		s = s..'t['..tostring(j)..'],'
	end
	s = s:sub(1, -2)..') end'
	insert(packs, loadstring(s)())
end

local REQUEST		= 0	rpc.REQUEST		= REQUEST
local RESPONSE		= 1	rpc.RESPONSE		= RESPONSE
local NOTIFICATION	= 2	rpc.NOTIFICATION	= NOTIFICATION

local Request = Class({
	new = function(self, id, rpc, name, to)		--luacheck:ignore
		self.id		= id
		self.rpc	= rpc
		self.name	= name
		self.to		= to
		self.completed	= false
		self.result	= nil
		self.err	= nil
	end,

	step = function(self, timeout)
		return self.rpc:step(timeout)
	end
})
rpc.Request = Request

local RPC = Class({
	new = function(self, timeout, request_seed)
		self.timeout		= timeout or 1
		self.request_id		= request_seed or 1
		self.max_size		= 64 * 1024
		self.methods		= { }
		self.requests		= { }
	end,

	add_method = function(self, name, func)
		self.methods[name] = func
	end,

	delete_method = function(self, name)
		self.methods[name] = nil
	end,

	send = function(self, msg, to) --luacheck:ignore
		print('RPC.send', msg, to)
	end,

	recv = function(self, timeout) --luacheck:ignore
		print('RPC.recv')
		return nil, nil -- msg, from
	end,

	[REQUEST] = function(self, from, id, method_name, params)
		local method = self.methods[method_name]
		local result
		if method ~= nil then
			result = pack(pcall(method, unpackn(params)))
		else
			result = pack(false, 'unknown method '..method_name)
		end
		local ok, err
		ok = removen(result, 1)
		if ok == false then
			err = removen(result, 1)
		end
		local msg = pack(RESPONSE, id, err, result)
		self:send(msg, from)
	end,

	find_request = function(self, id)
		for i,request in ipairs(self.requests) do
			if id == request.id then
				remove(self.requests, i)
				return request
			end
		end
		return nil
	end,

	[RESPONSE] = function(self, from, id, err, result) --luacheck:ignore
		-- TODO: check request queue
		local request = self:find_request(id)
		if request == nil then
			error('unknown response')
		elseif request.from ~= nil then
			local msg = pack(RESPONSE, request.from_id, err, result)
			self:send(msg, request.from)
		else
			request.completed	= true
			request.err		= err
			result			= result or pack()
			request.result		= packs[result.n](result)
			return request
		end
	end,

	notify = function(self, to, method, params)
		local msg = pack(NOTIFICATION, method, params)
		self:send(msg, to)
	end,

	[NOTIFICATION] = function(self, from, method, params) --luacheck:ignore
		method = self.methods[method]
		local ok, msg = xpcall(method, debug.traceback,
						unpackn(params or { n=0 }))
		if not ok then
			print('NOTIFICATION error: '..msg)
		end
	end,

	process = function(self, msg, from)
		assert(type(msg) == 'table', 'type '..type(msg)..' not a table.')
		local type = remove(msg, 1)
		return self[type](self, from, unpackn(msg))
	end,

	step = function(self, timeout)
		local msg, from = self:recv(timeout)
		if msg ~= nil then
			return self:process(msg, from)
		end
	end,

	call = function(self, name)			--luacheck:ignore
		assert(name, 'call name nil')
		return function(self, to, ...)		--luacheck:ignore
			local params	= pack(...)
			local id	= self.request_id
			self.request_id	= self.request_id + 1
			local request	= Request(id, self, name, to)
			insert(self.requests, request)
			request.msg 	= pack(REQUEST, id, name, params)
			return request
		end
	end,

	asynchronous = function(self, name)
		return function(...)
			return self:call(name)(self, ...)
		end
	end,

	synchronous = function(self, name, timeout)
		local func = self:asynchronous(name)
		return function(...)
			local req = func(...)
			req:step(timeout or 1)
			if not req.completed then
				error('timeout')
			end
			if req.err then
				error(req.err)
			end
			return unpackn(req.result)
		end
	end,

	__index = function(self, name)
		local value = rawget(self._class, name)
		if value ~= nil then
			return value
		end
		assert(name)
		return self:call(name)
	end,
})
rpc.RPC = RPC

return rpc
