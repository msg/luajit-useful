--
-- u s e f u l / r p c / m e s s a g e . l u a
--

local message = { }

local range		= require('useful.range')
local  uint8		=  range.uint8
local  uint16		=  range.uint16
local msgpack		= require('useful.range.msgpack')
local  encode		=  msgpack.encode
local  decode		=  msgpack.decode
local  FIXSTR		=  msgpack.FIXSTR
local  BIN8		=  msgpack.BIN8
local strings		= require('useful.strings')
local tables		= require('useful.tables')
local  serialize	=  tables.serialize

local HEADER_SIZE	= 12
message.HEADER_SIZE	= HEADER_SIZE

-- NOTE: these functions modify the incoming range (r8) which is useful
--       to append more messages before sending the output.

local encode_header = function(length, r8)
	local v16	= uint16.vla(1)
	v16[0]		= uint16.swap(length)
	encode('MSGPACK', r8)
	encode(v16, r8) -- encode a BIN8 containing length of payload
end
message.encode_header = encode_header

local encode_message = function(data, r8)
	local sr8	= r8:save()
	r8:pop_front(HEADER_SIZE)	-- make room for header
	local p8	= r8:save()
	encode(data, r8)
	p8.back		= r8.front
	sr8.back	= r8.front
	assert(p8.front[0] ~= 0x80,
		'it is bad here: '..p8.front[0]..'\n'..serialize(data, nil, '', '')..'\n'..
		strings.hexdump(sr8:to_string()))

	encode_header(#p8, sr8:save())
	return uint8.meta(sr8.front, r8.front)
end
message.encode_message = encode_message

local decode_header = function(r8)
	assert(r8:get_front()	== FIXSTR + 7,	'sync bad')
	assert(decode(r8)	== 'MSGPACK',	'sync MSGPACK not found')
	assert(r8:get_front()	== BIN8,	'length BIN8 not found')
	local length = decode(r8)
	return tonumber(uint16.swap(uint16.to_vla(length)[0]))
end
message.decode_header	= decode_header

local decode_message = function(r8)
	local length = decode_header(r8)
	assert(length <= #r8, 'invalid length')
	return decode(r8)
end
message.decode_message = decode_message

return message
