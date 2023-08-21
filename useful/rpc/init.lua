#!/usr/bin/env luajit
--
-- u s e f u l / r p c / i n i t . l u a
--
local rpc = { }

local  traceback	=  debug.traceback

local  insert		=  table.insert
local  remove		=  table.remove

local class		= require('useful.class')
local  Class		=  class.Class
			  require('useful.compatible')
local  pack		=  table.pack			-- luacheck:ignore
local  unpack		=  table.unpack			-- luacheck:ignore

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

-- packn - pack arguments and remove .n
local function packn(...)
	local t = pack(...)
	t.n = nil
	return t
end

local function unpackn(t, f, l)
	return unpack(t, f or 1, l or t.n)
end

local REQUEST		= 0	rpc.REQUEST		= REQUEST
local RESPONSE		= 1	rpc.RESPONSE		= RESPONSE
local NOTIFICATION	= 2	rpc.NOTIFICATION	= NOTIFICATION

local Request = Class({
	new = function(self, id, rpc, name, params)	--luacheck:ignore
		self.id		= id
		self.rpc	= rpc
		self.name	= name
		self.params	= params

		self.msg 	= packn(REQUEST, id, name, params)
		self.completed	= false
		self.result	= nil
		self.error	= nil
	end,
})
rpc.Request = Request

local RPC = Class({
	new = function(self, request_seed)
		self.request_id		= request_seed or 1
		self.methods		= { }
		self.requests		= { }
	end,

	add_method = function(self, name, func)
		self.methods[name] = func
	end,

	delete_method = function(self, name)
		self.methods[name] = nil
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

	request = function(self, name, ...)
		local request = Request(self.request_id, self, name, packn(...))
		self.request_id = self.request_id + 1
		insert(self.requests, request)
		return request
	end,

	notify = function(self, method, ...)		--luacheck:ignore
		return packn(NOTIFICATION, method, {...})
	end,

	[REQUEST] = function(self, id, method_name, params)
		local method = self.methods[method_name]
		local ok, result
		if method ~= nil then
			ok, result = xpcall(function()
				return packn(method(unpackn(params)))
			end, traceback)
		else
			result = packn('unknown method '..method_name)
		end
		if not ok then
			return packn(RESPONSE, id, result)
		else
			return packn(RESPONSE, id, nil, result)
		end
	end,

	[RESPONSE] = function(self, id, err, result)
		local request = self:find_request(id)
		if request == nil then
			error('unknown request id='..tostring(id))
		else
			request.completed	= true
			request.error		= err
			request.result		= result
		end
	end,

	[NOTIFICATION] = function(self, method_name, params) --luacheck:ignore
		local method = self.methods[method_name]
		if method ~= nil then
			local ok, err = xpcall(method, traceback, unpackn(params))
			if not ok then
				error('notify error: '..err)
			end
		else
			error('unknown method '..method_name)
		end
	end,

	process = function(self, msg)
		assert(type(msg) == 'table', 'type '..type(msg)..' not a table.')
		local type = msg[1]
		assert(0 <= type and type <= 2, 'invalid msg: '..tostring(type))
		return self[type](self, unpackn(msg, 2, msg.n))
	end,

	wrap = function(self, name)
		return function(...)
			return self:request(name, ...)
		end
	end,
})
rpc.RPC = RPC

return rpc
