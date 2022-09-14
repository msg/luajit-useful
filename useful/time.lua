--
-- u s e f u l / t i m e . l u a
--
local time = { }

-- wrapper around `struct timespec`
--   c = a - b
--   s=tv_sec n=tv_nsec
--   c = s.n.ppn
--   c = a - b
--   c.s = a.s - b.s
--   c.n = a.n - b.n
--   NOTE: Should sign of difference only carried in tv_sec? therefore:
--
--           abs(c) = abs(c.s) + c.n
--           c.s < 0:
--             c.n < 0: c.n = -c.n
--             c.n > 0: c.s = c.s + 1; c.n = 1e9 - c.n
--           c.s > 0:
--             c.n < 0: c.s = c.s - 1; c.n = 1e9 + c.n
--             c.n > 0: <nothing>
--
--         No, because manipulation of time requires the same operations
--         for all math operations.  So when outputting dt (or time), the
--         operations above would be required.
--
--         Also, if abs(ns) > 1e9 then adjustments need to be made:
--
--           n > 1e9: s = s + 1; n = n - 1e9
--           n < -1e9: s = s - 1; n = n + 1e9
--
--         This keeps the numbers from overflowing when doing many time
--         calculations.
--
local  floor	=  math.floor
local  modf	=  math.modf

local ffi	= require('ffi')
local  C	=  ffi.C
local  fstring	=  ffi.string
local  metatype	=  ffi.metatype
local  new	=  ffi.new
local  sizeof	=  ffi.sizeof

		  require('posix.time')

local umath	= require('useful.math')
local  divmod	=  umath.divmod
local timespec

local MILLI_HZ	= 1000
local MICRO_HZ	= 1000 * MILLI_HZ
local NANO_HZ	= 1000 * MICRO_HZ

local function fix_nano(ts)
	-- NOTE: this only handles overflow of < abs(NANO_HZ * 2)
	--       because of int32_t has a range of +/- 2G.
	while ts.tv_nsec > NANO_HZ do
		ts.tv_sec = ts.tv_sec + 1
		ts.tv_nsec = ts.tv_nsec - NANO_HZ
	end
	while ts.tv_nsec < 0 do
		ts.tv_sec = ts.tv_sec - 1
		ts.tv_nsec = ts.tv_nsec + NANO_HZ
	end
end
time.fix_nano = fix_nano

local function number_to_timespec(n)
	local i, f = modf(n, 1)
	return timespec(floor(i), floor(f * NANO_HZ))
end
time.number_to_timespec = number_to_timespec

local function timespec_to_number(ts)
	return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) / NANO_HZ
end
time.timespec_to_number = timespec_to_number

time.iso8601_fmt = '%Y%m%dT%H%M%S%Z'

function time.strftime(fmt, tm)
	local s = new('char[1024]')
	local rc = C.strftime(s, sizeof(s), fmt, tm)
	return fstring(s, rc)
end

function time.iso8601(ts)
	return time.strftime(time.iso8601_fmt, ts:gmtime())
end

time.secs = function(s)		return number_to_timespec(s)		end
time.msecs = function(ms)	return number_to_timespec(ms * MILLI_HZ)end
time.usecs = function(us)	return number_to_timespec(us * MICRO_HZ)end
time.nsecs = function(ns)	return number_to_timespec(ns * NANO_HZ)	end

local function make_timespec(v)
	if type(v) == 'number' then
		return number_to_timespec(v)
	else
		return v
	end
end

local function make_number(v)
	if type(v) == 'number' then
		return v
	else
		return timespec_to_number(v)
	end
end

local timespec_mt = {
	__add = function(a, b)
		b = make_timespec(b)
		local c = timespec(a.tv_sec + b.tv_sec, a.tv_nsec + b.tv_nsec)
		time.fix_nano(c)
		return c
	end,
	__sub = function(a, b)
		b = make_timespec(b)
		local c = timespec(a.tv_sec - b.tv_sec, a.tv_nsec - b.tv_nsec)
		time.fix_nano(c)
		return c
	end,
	__unm = function(ts)
		ts.tv_sec = -ts.tv_sec
		ts.tv_nsec = -ts.tv_nsec
	end,
	__mul = function(a, b)
		return number_to_timespec(make_number(a) * make_number(b))
	end,
	__div = function(a, b)
		return number_to_timespec(make_number(a) / make_number(b))
	end,
	__eq = function(a, b)
		return a.tv_sec == b.tv_sec and a.tv_nsec == b.tv_nsec
	end,
	__lt = function(a, b)
		if a.tv_sec == b.tv_sec then
			return a.tv_nsec < b.tv_nsec
		else
			return a.tv_sec < b.tv_sec
		end
	end,
	gmtime = function(ts)
		local t = new('int64_t[1]', ts.tv_sec)
		return C.gmtime(t)
	end,
	localtime = function(ts)
		local t = new('int64_t[1]', ts.tv_sec)
		return C.localtime(t)
	end,
	to_number = function(ts)
		return time.timespec_to_number(ts)
	end,
}
timespec_mt.__index = timespec_mt

timespec	= metatype('struct timespec', timespec_mt)
time.timespec	= timespec

function time.now(ts)
	ts = ts or timespec()
	if C.clock_gettime(C.CLOCK_REALTIME, ts) < 0 then
		ts = nil
	end
	return ts
end

function time.sleep(ts_or_s)
	if type(ts_or_s) == 'number' then
		ts_or_s = number_to_timespec(ts_or_s)
	end
	return C.clock_nanosleep(C.CLOCK_REALTIME, 0, ts_or_s, nil)
end

function time.dt(end_ts, begin_ts)
	return time.timespec_to_number(end_ts - begin_ts)
end

time.elapsed = function(start)
	return time.dt(time.now(), start)
end

time.timeout = function(start, timeout)
	return time.elapsed(start) > timeout
end

time.dhms = function(seconds)
	local days, hours, minutes
	minutes, seconds	= divmod(60, seconds)
	hours, minutes		= divmod(60, minutes)
	days, hours		= divmod(24, hours)
	return days, hours, minutes, seconds
end

return time
