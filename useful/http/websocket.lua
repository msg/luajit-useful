--
-- u s e f u l / h t t p / w e b s o c k e t . l u a
--
local websocket = { }

local ffi		= require('ffi')
local  cast		=  ffi.cast
local  new		=  ffi.new
local  sizeof		=  ffi.sizeof

local bit		= require('bit')
local  band		=  bit.band
local  bnot		=  bit.bnot
local  bor		=  bit.bor
local  bswap		=  bit.bswap
local  bxor		=  bit.bxor
local  rshift		=  bit.rshift

local status_		= require('useful.http.status')
local  Status		=  status_.Status
local protect		= require('useful.protect')
local  try1		=  protect.try1
local range		= require('useful.range')
local  char		=  range.char
local base64		= require('useful.range.base64')
local sha1		= require('useful.range.sha1')

local uuid	= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
websocket.uuid	= uuid

local opcodes = {
	CONTINUE	= 0,
	TEXT		= 1,
	BINARY		= 2,
	CLOSE		= 8,
	PING		= 9,
	PONG		= 10,
	[0]		= 'CONTINUE',
	[1]		= 'TEXT',
	[2]		= 'BINARY',
	[8]		= 'CLOSE',
	[9]		= 'PING',
	[10]		= 'PONG',
}
websocket.opcodes = opcodes

local close	= {
	NORMAL			= 1000,
	GOING_AWAY		= 1001,
	PROTOCOL_ERROR		= 1002,
	UNPROCESSABLE_INPUT	= 1003,
	RESERVED		= 1004,
	NOT_PROVIDED		= 1005,
	ABNORMAL		= 1006,
	INVALID_DATA		= 1007,
	POLICY_VIOLATION	= 1008,
	MESSAGE_TOO_BIG		= 1009,
	EXTENTION_REQUIRED	= 1010,
	[1000]			= 'NORMAL',
	[1001]			= 'GOING_AWAY',
	[1002]			= 'PROTOCOL_ERROR',
	[1003]			= 'UNPROCESSABLE_INPUT',
	[1004]			= 'RESERVED',
	[1005]			= 'NOT_PROVIDED',
	[1006]			= 'ABNORMAL',
	[1007]			= 'INVALID_DATA',
	[1008]			= 'POLICY_VIOLATION',
	[1009]			= 'MESSAGE_TOO_BIG',
	[1010]			= 'EXTENTION_REQUIRED',
}
websocket.close	= close

websocket.FIN		= 0x80

local recv_data = function(sock, i8, nbytes)
	return try1(sock:recv_all(i8.front, nbytes))
end

local xor = function(o8, len, mask)
	-- 32-bit xor
	local p32	= cast('uint32_t *', o8.front)
	local m32	= new('uint32_t[1]', mask)
	local len32	= band(len, bnot(3))
	for i=0,rshift(len32,2)-1 do
		p32[i]	= bxor(p32[i], m32[0])
	end

	-- 8-bit xor for last (upto 3) bytes.
	local p8	= o8.front
	local m8	= cast('uint8_t *', m32)
	for i=len32,len-1 do
		p8[i]	= bxor(p8[i], m8[band(i,3)])
	end
end
websocket.xor = xor

local swap16 = function(value)
	return rshift(bswap(value), 16)
end
websocket.swap16 = swap16

local swap64 = function(value)
	return bswap(value + 0LL) -- + 0LL to force 64-bits
end
websocket.swap64 = swap64

websocket.recv_packet = function(sock, r8)
	local o8	= r8:save()
	recv_data(sock, o8, 2)
	local byte	= o8:read_front()
	local fin	= band(byte, 0x80)
	local opcode	= band(byte, 0x0f)
	assert(band(byte, 0x70) == 0, 'invalid rsv bits')
	byte		= o8:read_front()
	local maskbit	= band(byte, 0x80)
	local len	= band(byte, 0x7f)
	if len < 0x7e then --luacheck:ignore
		-- have length
	elseif len == 0x7e then
		recv_data(sock, o8, sizeof('uint16_t'))
		len	= swap16(o8:read_front_type('uint16_t'))
	elseif len == 0x7f then
		recv_data(sock, o8, sizeof('uint64_t'))
		len	= swap64(o8:read_front_type('uint64_t'))
	end
	local mask
	if maskbit ~= 0 then
		recv_data(sock, o8, sizeof('uint32_t'))
		mask	= o8:read_front_type('uint32_t')
	end
	assert(len <= #o8, 'message too big')
	recv_data(sock, o8, len)
	o8.back		= o8.front + len
	if mask ~= nil then
		xor(o8, len, mask)
	end
	return o8, fin, opcode
end

local send_data = function(sock, i8, nbytes)
	local rc = sock:send_all(i8.front, nbytes)
	if rc < nbytes then
		error('send_data '..tonumber(rc)..' nbytes '..tostring(nbytes))
	end
	return rc
end

websocket.send_packet = function(sock, i8, fin, opcode, mask)
	local _, h8 = char.vla(14)
	local o8 = h8:save()
	o8:write_front(bor(fin, opcode))
	local mask_length = mask ~= nil and 0x80 or 0
	if #i8 < 126 then
		o8:write_front(bor(mask_length, #i8))
	elseif #i8 < 65536 then
		o8:write_front(bor(mask_length, 0x7e))
		o8:write_front_type('uint16_t', swap16(#i8))
	else
		o8:write_front(bor(mask_length, 0x7f))
		o8:write_front_type('uint64_t', swap64(#i8))
	end
	if mask ~= nil then
		o8:write_front_type('uint32_t', mask)
	end
	h8.back = o8.front
	send_data(sock, h8, #h8)
	if mask ~= nil then
		xor(i8, #i8, mask)
	end
	send_data(sock, i8, #i8)
end

local accept = function(s)
	local _, m8, t32, t, o8
	s	= s .. uuid
	_, m8	= char.vla(sha1.sha1_length(#s), s)
	_, t32	= sha1.sha1(m8, #s)
	t	= t32:cast(char)
	_, o8	= char.vla(base64.encode_length(#t))
	return base64.encode(t, o8):to_string()
end
websocket.accept = accept

websocket.send_close = function(sock, code, mask)
	local _,c8 = char.vla(2)
	c8:save():write_front_type('uint16_t', swap16(code))
	websocket.send_packet(sock, c8, websocket.FIN, opcodes.CLOSE, mask)
end

websocket.server_handshake = function(sock)
	local status	= Status(4096)

	status:setup(sock)
	status:recv()

	local upgrade	= status:get('upgrade')
	if upgrade ~= 'websocket' then
		error('upgrade is not websocket')
	end
	local key	= status:get('sec-websocket-key')
	local version	= status:get('sec-websocket-version')
	if key == '' or version ~= '13' then
		error('websocket key missing or version mismatch')
	end

	status:setup(sock)
	status:set('Upgrade', 'websocket')
	status:set('Connection', 'Upgrade')
	status:set('Sec-WebSocket-Accept', websocket.accept(key))
	status:set('Sec-WebSocket-Protocol', 'schedulerserverws')
	status:send_response(101, 'Switching Protocols')
end

local function random16()
	local f = io.open('/dev/urandom')
	local d = f:read(16)
	f:close()
	local i8 = char.from_string(d)
	local _, o8 = char.vla(base64.encode_length(16))
	local r8 = base64.encode(i8, o8)
	return r8:to_string()
end

websocket.client_handshake = function(sock, options)
	options		= options or { }
	local status	= Status(4096)
	local key	= options.key or random16()
	status:setup(sock)
	status:set('Upgrade', 'websocket')
	status:set('Connection', 'Upgrade')
	status:set('Sec-WebSocket-Version', '13')
	status:set('Sec-WebSocket-Key', key)
	status:set('Sec-WebSocket-Protocol', options.protocol or 'websocket')
	status:send_request('GET', '/')
	status:recv()

	local actual_accept = status:get('Sec-WebSocket-Accept', '')
	assert(actual_accept == accept(key), 'invalid accept')
end

return websocket
