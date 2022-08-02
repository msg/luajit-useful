
# luajit useful library

This library has been created from years of development of applications
to simplify and speed the process.  It also includes a couple of utilities
from 3rd party developers.

It is also designed to be embedded into projects so they can become self-
contained.

It uses the *luajit posix library* which is an api that is a luajit ffi
interface to posix interfaces.  It also includes linux apis that aren't
necessarily posix compliant.  This library may change it's name as it
is not truly posix compliant.

## Installation

## APIS

### `useful.scheduler`

```
sceduler = require('useful.scheduler')
threads = scheduler.pool
thread = scheduler.spawn(func, ...)
scheduler.step()
scheduler.yield()
scheduler.stop(thread)
scheduler.yield(...)
scheduler.sleep(time, ...)
scheduler.check(predicate, ...)
shceduler.exit(...)
scheduler.wait(id, ...)
scheduler.timed_wait(id, time, ...)
scheduler.signal(id)
scheduler.on_error(error_func)
```

### `useful.rpc`

NOTE: this is subjet to change.  I want to use `scheduler.step()` above
to hanle `RPC` communication.  So the api is likely to change.

```
useful_rpc = require('useful.rpc')
rpc = useful_rpc.RPC(timeout, request_seed)
rpc:add_method(name, func)
rpc:delete_method(name)
rpc:send(msg, to)
msg, from = rpc:recv(timeout)
creq = rpc:step(timeout) -- creq: completed request or nil
acall = rpc:asynchronous(name)
req = acall(...)
scall = rpc:synchronous(name, timeout)
results = pack(scall(...))
```
