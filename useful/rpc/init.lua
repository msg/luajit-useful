#!/usr/bin/env luajit
--
-- u s e f u l / r p c / i n i t . l u a
--
local rpc = { }

local  insert		=  table.insert
local  remove		=  table.remove

local class		= require('useful.class')
local  Class		=  class.Class
local range		= require('useful.range')
local  uint8		=  range.uint8
local  uint16		=  range.uint16
local strings		= require('useful.strings')
local system		= require('useful.system')
local  pack		=  system.pack
local  unpack		=  system.unpack
local tables		= require('useful.tables')
local  serialize	=  tables.serialize
local threading		= require('useful.threading')

local msgpack		= require('useful.range.msgpack')
local  encode		= msgpack.encode
local  decode		= msgpack.decode
local  FIXSTR		= msgpack.FIXSTR
local  BIN8		= msgpack.BIN8

local HEADER_SIZE		= 12
rpc.HEADER_SIZE	= HEADER_SIZE

-- NOTE: these functions modify the incoming range (r8) which is useful
--       to append more messages before sending the output.

local encode_header = function(length, r8)
	local v16	= uint16.vla(1)
	v16[0]		= uint16.swap(length)
	encode('MSGPACK', r8)
	encode(v16, r8)
end

local encode_packet = function(data, r8)
	local sr8	= r8:save()
	r8:pop_front(HEADER_SIZE)	-- make room for header
	local p8	= r8:save()
	encode(data, r8)
	p8.back		= r8.front
	sr8.back = r8.front
	assert(p8.front[0] ~= 0x80,
		'it is bad here: '..p8.front[0]..'\n'..serialize(data, nil, '', '')..'\n'..
		strings.hexdump(sr8:to_string()))

	encode_header(#p8, sr8:save())
	return uint8.meta(sr8.front, r8.front)
end

local decode_header = function(r8)
	assert(r8:get_front()	== FIXSTR + 7,	'sync bad')
	assert(decode(r8)	== 'MSGPACK',	'sync MSGPACK not found')
	assert(r8:get_front()	== BIN8,	'length BIN8 not found')
	local length = decode(r8)
	return tonumber(uint16.swap(uint16.to_vla(length)[0]))
end
rpc.decode_header	= decode_header

local decode_packet = function(r8)
	local length = decode_header(r8)
	assert(length <= #r8, 'invalid length')
	return decode(r8)
end

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

local function unpackn(args)
	return unpack(args, 1, args.n)
end

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

	encode_message = function(self, msg, r8)	--luacheck:ignore
		return encode_packet(msg, r8)
	end,

	decode_message = function(self, r8)		--luacheck:ignore
		return decode_packet(r8)
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

	wrap = function(self, name)
		return function(...)
			return self:call(name)(self, ...)
		end
	end,

	synchronous = function(self, name, timeout)
		local func = self:wrap(name)
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

rpc.ThreadingRPC = Class(RPC, {
	new = function(self, from, to, timeout)
		RPC.new(self, timeout)
		self.from	= from
		self.to		= to
	end,

	send = function(self, msg, to)
		local v8 = uint8.vla(8192)
		local r8 = uint8.from_vla(v8)
		local m8 = self:encode_message(msg, r8)
		local s = m8:to_string()
		return threading.send(to, s, self.from)
	end,

	recv = function(self, timeout)
		local msgs = threading.receive(self.from, timeout, 1)
		if #msgs ~= 0 then
			local msg,from = unpackn(msgs[1])
			local r8 = uint8.from_string(msg)
			msg = self:decode_message(r8)
			return msg,from
		else
			return nil, nil -- msg, from
		end
	end,

	wrap = function(self, name)
		return function(...)
			local req = RPC.wrap(self, name)(...)
			self:send(req.msg, self.to)
			return req
		end
	end,

	__index = RPC.__index,
})

return rpc
