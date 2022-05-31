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
local range_rpc		= require('useful.range.rpc')
local  decode_header	=  range_rpc.decode_header
local  RPC		=  range_rpc.RPC
local  HEADER_SIZE	=  range_rpc.HEADER_SIZE

rpc_socket.TCP_RPC = Class(RPC, {
	new = function(self, sock, size, timeout, synchronous)
		RPC.new(self, timeout, synchronous)
		self.size	= size
		self.sock	= sock
	end,

	send = function(self, msg, to)			--luacheck:ignore
		local _,o8	= uint8.vla(self.size)
		local m8	= self:encode_message(msg, o8)
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
