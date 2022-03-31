#!/usr/bin/luajit
--
-- u s e f u l / n e t w o r k . l u a
--
local network = { }

local  sprintf	=  string.format

local bit	= require('bit')
local  arshift	=  bit.arshift
local  band	=  bit.band
local  bnot	=  bit.bnot
local  bor	=  bit.bor
local  bswap	=  bit.bswap
local  bxor	=  bit.bxor
local  lshift	=  bit.lshift
local  rshift	=  bit.rshift
local  rol	=  bit.rol
local  ror	=  bit.ror
local  tobit	=  bit.tobit
local  tohex	=  bit.tohex

local bits	= require('useful.bits')
local  getbits	=  bits.getbits
local json	= require('useful.json')

network.iptos = function(ip)
	local octets = { }
	for i=3,0,-1 do
		table.insert(octets, sprintf('%d', getbits(ip, i*8, 8)))
	end
	return table.concat(octets, '.')
end

network.stoip = function(s)
	local ip = 0
	for octet in s:gmatch('%d+') do
		ip = bor(lshift(ip, 8), tonumber(octet))
	end
	return ip
end

network.mactos = function(mac)
	local octets = { }
	for i=5,0,-1 do
		table.insert(octets, sprintf('%02x', getbits(mac, i*8, 8)))
	end
	return table.concat(octets, ':')
end

network.stomac = function(s)
	local mac = 0LL
	for octet in s:gmatch('[0-9A-Fa-f]+') do
		mac = bor(lshift(mac, 8), tonumber(octet, 16))
	end
	return mac
end

network.gateway = function(ifname)
	local routes	= json.decode(io.popen('ip -j route'):read('*a'))
	for _,route in ipairs(routes) do
		if ifname ~= nil and route.dev ~= ifname then
		elseif route.gateway ~= nil then
			return network.stoip(route.gateway)
		end
	end
end

network.config = function(ifname)
	local address	= json.decode(io.popen('ip -j address show'):read('*a'))
	for _,entry in ipairs(address) do
		if entry.ifname ~= ifname then
		elseif entry.addr_info == nil then
		elseif entry.addr_info[1] == nil then
		else
			local info	= entry.addr_info[1]
			local addr	= info['local']
			local ip	= network.stoip(addr)
			local nm	= bnot(lshift(1,32-info.prefixlen)-1)
			local mac	= network.stomac(entry.address)
			return ip, nm, mac
		end
	end
end

network.is_multicast = function(ip)
	return band(ip, 0xf0000000) == 0xe0000000
end

network.multicast_to_mac = function(ip)
	return bor(0x000001005e000000LL, band(ip, 0x007fffff))
end

return network
