#!/usr/bin/luajit
--
-- u s e f u l / r p c / s o c k e t . l u a
--

local rpc_socket = { }

local class		= require('useful.class')
local  Class		=  class.Class
local range		= require('useful.range')
local  uint8		=  range.uint8
local msgpack		= require('useful.range.msgpack')
local  decode		=  msgpack.decode
local rpc		= require('useful.rpc')
local  RPC		=  rpc.RPC
local rpc_message	= require('useful.rpc.message')
local  decode_header	=  rpc_message.decode_header
local  encode_message	=  rpc_message.encode_message
local  HEADER_SIZE	=  rpc_message.HEADER_SIZE

rpc_socket.TCP_RPC = Class(RPC, {
	new = function(self, sock, size, timeout)
		RPC.new(self, timeout)
		self.size	= size
		self.sock	= sock
	end,

	send = function(self, msg, to)			--luacheck:ignore
		local _,o8	= uint8.vla(self.size)
		local m8	= encode_message(msg, o8)
		local rc	= self.sock:send_all(m8.front, #m8)
		return rc
	end,

	recv = function(self, timeout)
		local _,in8	= uint8.vla(self.size)
		local i8	= in8:save()
		self.sock:set_timeout(timeout)
		i8.back = i8.front + self.sock:recv_all(i8.front, HEADER_SIZE)
		local length	= decode_header(i8)
		assert(length <= #in8)
		i8		= in8:save()
		i8.back = i8.front + self.sock:recv_all(i8.front, length)
		return decode(i8), nil
	end,

	__index = RPC.__index,
})

return rpc_socket
