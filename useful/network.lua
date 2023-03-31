--
-- u s e f u l / n e t w o r k . l u a
--
local network = { }

local  sprintf	=  string.format

local bit	= require('bit')
local  band	=  bit.band
local  bnot	=  bit.bnot
local  bor	=  bit.bor
local  lshift	=  bit.lshift

local bits	= require('useful.bits')
local  getbits	=  bits.getbits
local json	= require('useful.json')

local iptos = function(ip)
	local octets = { }
	for i=3,0,-1 do
		table.insert(octets, sprintf('%d', getbits(ip, i*8, 8)))
	end
	return table.concat(octets, '.')
end
network.iptos = iptos

local stoip = function(s)
	local ip = 0
	for octet in s:gmatch('%d+') do
		ip = bor(lshift(ip, 8), tonumber(octet))
	end
	return ip
end
network.stoip = stoip

local mactos = function(mac)
	local octets = { }
	for i=5,0,-1 do
		table.insert(octets, sprintf('%02x', getbits(mac, i*8, 8)))
	end
	return table.concat(octets, ':')
end
network.mactos = mactos

local stomac = function(s)
	local mac = 0LL
	for octet in s:gmatch('[0-9A-Fa-f]+') do
		mac = bor(lshift(mac, 8), tonumber(octet, 16))
	end
	return mac
end
network.stomac = stomac

network.gateway = function(ifname)
	local routes	= json.decode(io.popen('ip -j route'):read('*a'))
	for _,route in ipairs(routes) do
		if ifname ~= nil and route.dev ~= ifname then --luacheck:ignore
		elseif route.gateway ~= nil then
			return stoip(route.gateway)
		end
	end
end

local interfaces = function()
	local interfaces = { }
	local address	= json.decode(io.popen('ip -j address show'):read('*a'))
	for _,entry in ipairs(address) do
		local info	= entry.addr_info[1]
		if info then
			local addr	= info['local']
			local nm	= bnot(lshift(1,32-info.prefixlen)-1)
			local mac	= stomac(entry.address)
			local interface = {
				ifname	= entry.ifname,
				ip	= addr,
				nm	= iptos(nm),
				mac	= mactos(mac),
			}
			table.insert(interfaces, interface)
		end
	end
	return interfaces
end
network.interfaces = interfaces

network.config = function(ifname)
	-- TODO: handle interfaces with multiple addresses
	for _,interface in ipairs(interfaces()) do
		if interface.ifname == ifname then
			return interface.ip, interface.nm, interface.mac
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
