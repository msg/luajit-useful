--
-- u s e f u l / r p c / m s g p a c k . l u a
--

local msgpack = { }

local range		= require('useful.range')
local  uint8		=  range.uint8
local  uint16		=  range.uint16
local msgpack_		= require('useful.range.msgpack')
local  encode		=  msgpack_.encode
local  decode		=  msgpack_.decode
local  FIXSTR		=  msgpack_.FIXSTR
local  BIN8		=  msgpack_.BIN8
local strings		= require('useful.strings')
local tables		= require('useful.tables')
local  serialize	=  tables.serialize

-- message: FIXSTR+3 M S G BIN8 BINLEN LENMSB LENLSB data:LEN
--          8-bytes(header) + LEN-bytes
local HEADER_SIZE	= 8
msgpack.HEADER_SIZE	= HEADER_SIZE
msgpack.MAX_SIZE	= 64 * 1024

-- NOTE: these functions modify the incoming range (r8) which is useful
--       to append more messages before sending the output.

local encode_header = function(length, r8)
	local v16	= uint16.vla(1)
	v16[0]		= uint16.swap(length)
	encode('MSG', r8)
	encode(v16, r8) -- encode a BIN8 containing length of payload
end
msgpack.encode_header = encode_header

local encode_message = function(data, r8)
	r8		= r8:save()
	local sr8	= r8:save()
	r8:pop_front(HEADER_SIZE)	-- make room for header
	local p8	= r8:save()
	encode(data, r8)
	p8.back		= r8.front
	sr8.back	= r8.front
	-- message should not be a ZERO length map
	if p8.front[0] == 0x80 then
		return nil, 'it is bad here: '..p8.front[0]..'\n'
				..serialize(data, nil, '', '')..'\n'
				..strings.hexdump(sr8:to_string())
	end
	encode_header(#p8, sr8:save())
	return uint8.meta(sr8.front, r8.front)
end
msgpack.encode_message = encode_message

local decode_header = function(r8)
	local c = r8:get_front()
	if c ~= FIXSTR + 3 then
		return nil, 'sync bad c='..c
	elseif decode(r8) ~= 'MSG' then
		return nil, 'sync MSG not found'
	elseif r8:get_front() ~= BIN8 then
		return nil, 'BIN8 not found'
	else
		local length = decode(r8)
		return tonumber(uint16.swap(uint16.to_vla(length)[0]))
	end
end
msgpack.decode_header = decode_header

local decode_payload = function(r8, length)
	assert(length <= #r8, 'length smaller then range')
	return decode(r8)
end
msgpack.decode_payload = decode_payload

return msgpack
