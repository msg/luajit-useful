#!/usr/bin/luajit
--
-- h t t p / c o n n e c t i o n . l u a
--
local connection = { }

local  insert	=  table.insert
local  concat	=  table.concat

local class	= require('useful.class')
local  Class	=  class.Class
local status	= require('useful.http.status')
local  Status	=  status.Status
local range	= require('useful.range')
local  int8	=  range.int8
local rbase64	= require('useful.range.base64')
local rstring	= require('useful.range.string')
local  rstrip	=  rstring.rstrip
local socket	= require('useful.socket')

local Request = Status
local Response = Status

local Transaction = Class({
	new = function(self, request_size, response_size)
		self.request	= Request(request_size)
		self.response	= Response(response_size or request_size)
	end,

	reset = function(self)
		self.request:reset()
		self.response:reset()
			self.request:reset()
			self.response:reset()
	end,

	set_sock = function(self, sock)
		self.request:set_sock(sock)
		self.response:set_sock(sock)
	end
})
connection.Transaction = Transaction

local url_re = 'http://([^:/]+)(:?[^/]*)(/?.*)'
local parse_url = function(url)
	local host, port, path = url:match(url_re)
	assert(host ~= nil, 'bad url "'..url..'"')
	if port == '' then
		port = 80
	else
		port = tonumber(port:sub(2))
	end
	if path == '' then
		path = '/'
	end
	return host, port, path
end
connection.parse_url = parse_url

local base64_encode = function(s)
	local i8	= int8.from_string(s)
	local _,o8	= int8.vla(rbase64.encode_length(#s))
	return rbase64.encode(i8, o8).s
end
connection.base64_encode = base64_encode

local printf = require('useful.stdio').printf

connection.dump_status = function(status) --luacheck:ignore
	if status.status then
		local line = status.status
		printf('status=<%s>\n', line.s)
	end
	for i=0,status.nheader-1 do
		local header = status.header[i]
		rstrip(header)
		printf('<%s>\n', header.s)
	end
end

connection.url_read = function(url, options)
	option = options or {}
	options.host, options.port, options.path = parse_url(url)
	sock = socket.TCP()
	assert(sock:connect(options.host, options.port) == 0)
	local transaction = Transaction(options.max_size or 32768)
	transaction:reset()
	transaction.request:set('Host', options.host)
	if options.keep_alive ~= nil then
		transaction.request:set('Keep-Alive', options.keep_alive)
		transaction.request:set('Connection', 'keep-alive')
	end
	transaction.request:set('User-Agent', 'connection.lua')
	transaction.request:set('Accept', options.accept or '*/*')
	if options.user_password ~= nil then
		local encoded = base64_encode(options.user_password)
		transaction.request:set('Authorization', 'Basic '..encoded)
	end
	if options.output ~= nil then
		transaction.request:set('Content-Length', tostring(#options.output))
	end
	--connection.dump_status(transaction.request)
	transaction:set_sock(sock)
	transaction.request:send_request(options.method or 'GET', options.path)
	if output ~= nil then
		local o = int8.from_string(output)
		transaction.request:write(o.front, #o)
	end

	transaction.response:recv()
	local encoding = transaction.response:get('Transfer-Encoding')
	local chunks = { }
	if encoding == 'chunked' then
		repeat
			local size = rstrip(transaction.response:read_line())
			size = tonumber('0x'..size.s)
			local chunk = transaction.response:read(size)
			if transaction.response:read_line().s ~= '\r\n' then
				error('invalid transfer')
			end
			insert(chunks, chunk.s)
		until size == 0
	else
		length = tonumber(transaction.response:get('Content-Length','0'))
		while length > 0 do
			local s = transaction.response:read(length)
			length = length - #s
			insert(chunks, s.s)
		end
	end
	sock:close()
	return concat(chunks)
end

return connection
