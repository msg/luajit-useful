#!/usr/bin/luajit
--
-- u s e f u l / r p c / s o c k e t . l u a
--

local socket = { }

local class		= require('useful.class')
local  Class		=  class.Class
local range		= require('useful.range')
local  uint8		=  range.uint8
local msgpack		= require('useful.range.msgpack')
local  decode		=  msgpack.decode
local rpc		= require('useful.rpc')
local  RPC		=  rpc.RPC
local message		= require('useful.rpc.message')
local  decode_header	=  message.decode_header
local  encode_message	=  message.encode_message
local  HEADER_SIZE	=  message.HEADER_SIZE

socket.TCP_RPC = Class(RPC, {
	new = function(self, sock, size, timeout)
		RPC.new(self, timeout)
		self.size		= size
		self.sock		= sock
		self.vla, self.u8	= uint8.vla(sick)
	end,

	send = function(self, msg, to)			--luacheck:ignore
		local o8	= self.u8:save()
		local m8	= encode_message(msg, o8)
		local rc	= self.sock:send_all(m8.front, #m8)
		return rc
	end,

	recv = function(self, timeout)
		local i8	= self.u8:save()
		self.sock:set_timeout(timeout)
		i8.back = i8.front + self.sock:recv_all(i8.front, HEADER_SIZE)
		local length	= decode_header(i8)
		assert(length <= #in8)
		i8		= self.u8:save()
		i8.back = i8.front + self.sock:recv_all(i8.front, length)
		return decode(i8), nil
	end,

	__index = RPC.__index,
})

return socket
