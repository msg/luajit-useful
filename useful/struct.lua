--[[
 * Copyright (c) 2015-2020 Iryont <https://github.com/iryont/lua-struct>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
]]

local  floor		=  math.floor
local  frexp		=  math.frexp
local  ldexp		=  math.ldexp

local  byte		=  string.byte
local  char		=  string.char
local  rep		=  string.rep
local  reverse		=  string.reverse

local  concat		=  table.concat
local  insert		=  table.insert
local  remove		=  table.remove

local unpack = table.unpack or _G.unpack -- luacheck:ignore

local struct = {}

function struct.pack(format, ...)
  local stream = {}
  local vars = {...}
  local endianness = true

  for i = 1, format:len() do
    local opt = format:sub(i, i)

    if opt == '<' then
      endianness = true
    elseif opt == '>' then
      endianness = false
    elseif opt:find('[bBhHiIlL]') then
      local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
      local val = tonumber(remove(vars, 1))

      local bytes = {}
      for _ = 1, n do
        insert(bytes, char(val % (2 ^ 8)))
        val = floor(val / (2 ^ 8))
      end

      if not endianness then
        insert(stream, reverse(concat(bytes)))
      else
        insert(stream, concat(bytes))
      end
    elseif opt:find('[fd]') then
      local val = tonumber(remove(vars, 1))
      local sign = 0

      if val < 0 then
        sign = 1
        val = -val
      end

      local mantissa, exponent = frexp(val)
      if val == 0 then
        mantissa = 0
        exponent = 0
      else
        mantissa = (mantissa * 2 - 1) * ldexp(0.5, (opt == 'd') and 53 or 24)
        exponent = exponent + ((opt == 'd') and 1022 or 126)
      end

      local bytes = {}
      if opt == 'd' then
        val = mantissa
        for _ = 1, 6 do
          insert(bytes, char(floor(val) % (2 ^ 8)))
          val = floor(val / (2 ^ 8))
        end
      else
        insert(bytes, char(floor(mantissa) % (2 ^ 8)))
        val = floor(mantissa / (2 ^ 8))
        insert(bytes, char(floor(val) % (2 ^ 8)))
        val = floor(val / (2 ^ 8))
      end

      insert(bytes, char(floor(exponent * ((opt == 'd') and 16 or 128) + val) % (2 ^ 8)))
      val = floor((exponent * ((opt == 'd') and 16 or 128) + val) / (2 ^ 8))
      insert(bytes, char(floor(sign * 128 + val) % (2 ^ 8)))
      val = floor((sign * 128 + val) / (2 ^ 8)) -- luacheck:ignore

      if not endianness then
        insert(stream, reverse(concat(bytes)))
      else
        insert(stream, concat(bytes))
      end
    elseif opt == 's' then
      insert(stream, tostring(remove(vars, 1)))
      insert(stream, char(0))
    elseif opt == 'c' then
      local n = format:sub(i + 1):match('%d+')
      local str = tostring(remove(vars, 1))
      local len = tonumber(n)
      if len <= 0 then
        len = str:len()
      end
      if len - str:len() > 0 then
        str = str .. rep(' ', len - str:len())
      end
      insert(stream, str:sub(1, len))
      i = i + n:len() -- luacheck:ignore
    elseif opt == 'x' then
      insert(stream, '\0')
      i = i + 1 -- luacheck:ignore
    end
  end

  return concat(stream)
end

function struct.unpack(format, stream, pos)
  local vars = {}
  local iterator = pos or 1
  local endianness = true

  for i = 1, format:len() do
    local opt = format:sub(i, i)

    if opt == '<' then
      endianness = true
    elseif opt == '>' then
      endianness = false
    elseif opt:find('[bBhHiIlL]') then
      local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
      local signed = opt:lower() == opt

      local val = 0
      for j = 1, n do
        local byte_ = byte(stream:sub(iterator, iterator))
        if endianness then
          val = val + byte_ * (2 ^ ((j - 1) * 8))
        else
          val = val + byte_ * (2 ^ ((n - j) * 8))
        end
        iterator = iterator + 1
      end

      if signed and val >= 2 ^ (n * 8 - 1) then
        val = val - 2 ^ (n * 8)
      end

      insert(vars, floor(val))
    elseif opt:find('[fd]') then
      local n = (opt == 'd') and 8 or 4
      local x = stream:sub(iterator, iterator + n - 1)
      iterator = iterator + n

      if not endianness then
        x = reverse(x)
      end

      local sign = 1
      local mantissa = byte(x, (opt == 'd') and 7 or 3) % ((opt == 'd') and 16 or 128)
      for _ = n - 2, 1, -1 do
        mantissa = mantissa * (2 ^ 8) + byte(x, i)
      end

      if byte(x, n) > 127 then
        sign = -1
      end

      local exponent = (byte(x, n) % 128) *
			((opt == 'd') and 16 or 2) +
			floor(byte(x, n - 1) /
			((opt == 'd') and 16 or 128))
      if exponent == 0 then
        insert(vars, 0.0)
      else
        mantissa = (ldexp(mantissa, (opt == 'd') and -52 or -23) + 1) * sign
        insert(vars, ldexp(mantissa, exponent - ((opt == 'd') and 1023 or 127)))
      end
    elseif opt == 's' then
      local bytes = {}
      for j = iterator, stream:len() do
        if stream:sub(j,j) == char(0) or  stream:sub(j) == '' then
          break
        end

        insert(bytes, stream:sub(j, j))
      end

      local str = concat(bytes)
      iterator = iterator + str:len() + 1
      insert(vars, str)
    elseif opt == 'c' then
      local n = format:sub(i + 1):match('%d+')
      local len = tonumber(n)
      if len <= 0 then
        len = remove(vars)
      end

      insert(vars, stream:sub(iterator, iterator + len - 1))
      iterator = iterator + len
      i = i + n:len() -- luacheck:ignore
    elseif opt == 'x' then
      i = i + 1 -- luacheck:ignore
    end
  end

  return unpack(vars)
end

return struct
