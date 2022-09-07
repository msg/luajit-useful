--
-- u s e f u l / r p c / t h r e a d i n g . l u a
--
local threading = { }

local class		= require('useful.class')
local  Class		=  class.Class
local range		= require('useful.range')
local  uint8		=  range.uint8
local rpc		= require('useful.rpc')
local  RPC		=  rpc.RPC
local  unpackn		=  rpc.unpackn
local message		= require('useful.rpc.message')
local  decode_message	=  message.decode_message
local  encode_message	=  message.encode_message

threading.ThreadingRPC = Class(RPC, {
	new = function(self, from, to, timeout)
		RPC.new(self, timeout)
		self.from	= from
		self.to		= to
	end,

	send = function(self, msg, to)
		local v8 = uint8.vla(8192)
		local r8 = uint8.from_vla(v8)
		local m8 = encode_message(msg, r8)
		local s = m8:to_string()
		return threading.send(to, s, self.from)
	end,

	recv = function(self, timeout)
		local msgs = threading.receive(self.from, timeout, 1)
		if #msgs ~= 0 then
			local msg,from = unpackn(msgs[1])
			local r8 = uint8.from_string(msg)
			msg = decode_message(r8)
			return msg,from
		else
			return nil, nil -- msg, from
		end
	end,

	asynchronous = function(self, name)
		return function(...)
			local req = RPC.asynchronous(self, name)(...)
			self:send(req.msg, self.to)
			return req
		end
	end,

	__index = RPC.__index,
})

return threading
