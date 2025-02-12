--
-- u s e f u l / n e t w o r k . l u a
--
local network = { }

local  sprintf		=  string.format

local ffi		= require('ffi')
local  C		=  ffi.C
local  cast		=  ffi.cast
local  copy		=  ffi.copy
local  fstring		=  ffi.string
local  new		=  ffi.new
local  sizeof		=  ffi.sizeof
local bit		= require('bit')
local  band		=  bit.band
local  bor		=  bit.bor
local  lshift		=  bit.lshift

local bits		= require('useful.bits')
local  getbits		=  bits.getbits
local json		= require('useful.json')
local system		= require('useful.system')
local  errno_string	=  system.errno_string


local iptos = function(ip)
	local octets = { }
	for i=3,0,-1 do
		table.insert(octets, sprintf('%d', getbits(ip, i*8, 8)))
	end
	return table.concat(octets, '.')
end
network.iptos = iptos

local stoip = function(s)
	local ip = 0ULL
	for octet in s:gmatch('%d+') do
		ip = bor(lshift(ip, 8), tonumber(octet))
	end
	return tonumber(ip)
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
	return json.decode(io.popen('ip -j address show'):read('*a'))
end
network.interfaces = interfaces

local assertrc = function(r, msg)
	if r < 0 then
		error(msg..':'..errno_string())
	end
end
local addresses = function()
	local addresses	= { }
	local s		= C.socket(C.AF_INET, C.SOCK_DGRAM, 0)
	assertrc(s, 'socket')
	local ifca	= new('struct ifconf[1]')
	local ifc	= ifca + 0
	local len	= 2048
	local buf	= new('char[?]', len)
	ifc.ifc_len	= len
	ifc.ifcu_buf	= buf
	local ifra	= new('struct ifreq[1]')
	local ifr	= ifra + 0

	local r = C.ioctl(s, C.SIOCGIFCONF, ifc)
	assertrc(r, 'ioctl SIOCGIFCONF')
	local ifre	= cast('struct ifreq *', ifc.ifcu_buf + ifc.ifc_len)
	local ifrp	= cast('struct ifreq *', ifc.ifcu_buf)
	while ifrp < ifre do
		local inaddr = cast('struct sockaddr_in *', ifrp.ifr_addr)
		local address = {
			ifname	= fstring(ifrp.ifr_name),
			ip	= fstring(C.inet_ntoa(inaddr.sin_addr)),
		}
		copy(ifr.ifr_name, ifrp.ifr_name, sizeof(ifr.ifr_name));
		inaddr	= cast('struct sockaddr_in *', ifr.ifr_netmask)
		r = C.ioctl(s, C.SIOCGIFNETMASK, ifr)
		assertrc(r, 'ioctl SIOCFGNETMASK')
		address.nm	= fstring(C.inet_ntoa(inaddr.sin_addr))
		r = C.ioctl(s, C.SIOCGIFHWADDR, ifr)
		assertrc(r, 'ioctl SIOCGIFHWADDR')
		local mac = ''
		for i=0,5 do
			local c = i == 0 and '' or ':'
			mac = mac..sprintf("%s%02x", c, band(ifr.ifr_hwaddr.sa_data[i], 0xff))
		end
		address.mac = mac
		table.insert(addresses, address)
		ifrp = ifrp + 1
	end
	return addresses
end
network.addresses = addresses

network.config = function(ifname)
	-- TODO: handle interfaces with multiple addresses
	for _,interface in ipairs(addresses()) do
		if interface.ifname == ifname then
			return interface.ip, interface.nm, interface.mac
		end
	end
end

network.is_multicast = function(ip)
	return band(ip+0LL, 0xf0000000ULL) == 0xe0000000ULL
end

network.multicast_to_mac = function(ip)
	return bor(0x000001005e000000ULL, band(ip+0LL, 0x007fffffULL))
end

return network
