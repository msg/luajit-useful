#include <pthread.h>
#include <time.h>
#include <string.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

typedef struct proc {
	lua_State *lua;
	pthread_cond_t cond;
	int nargs;
} proc;

int luaopen_threading(lua_State *lua);

static lua_State *luax = NULL; /* used to store message info */

static pthread_mutex_t kernel_access = PTHREAD_MUTEX_INITIALIZER;

/*
 * NOTES: this code creates a private lua_State `luax` that handles all the
 * intercommunication between threads.  a single global table `channels`
 * is created.
 * - `threading.start(func)` uses `lua_dump` and adds the function
 *   `func` to a new `pthread/lua_State` created with an "empty" environment.
 * - `threading.send(channel, ...)` adds `...` (must be tostring-able) to
 *   `channels[channel].queue` which is the private `luax`.
 * - `threading.receive(channel, timeout)` waits `timeout` seconds if
 *   `channels[channel].queue` is empty.  Otherwise moves all entries
 *   in `channels[channel].queue` onto the `pthread/lua_State` stack
 * - `threading.exit()` must be called on the initial *main* thread. so
 *   all `pthread/lua_State` cleanup and exits.
 *
 * optimizations/updates:
 * - don't use private `luax` for management.  Custom `C` code to maintain
 *   queue data is one option.  But support *primitive* (boolean, number, etc)
 *   data.  Another option is to add queue and wait data to the
 *   receiving `pthread/lua_State`.  `channels[channel]` could actually name
 *   a `pthread/lua_State`.  Then `channel` becomes unique.  The benefit is
 *   the .queue parameter doesn't need to move.  The question of how to manage
 *   thread synchronization.
 */

static proc *get_self(lua_State *lua) {
	// return `proc *` grabbed from lua registry
	proc *p;
	lua_getfield(lua, LUA_REGISTRYINDEX, "_SELF");
	p = (proc *)lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	return p;
}

static void get_channel_entry(const char *channel) {
	// put `channels[channel]` on stack
	lua_getfield(luax, LUA_GLOBALSINDEX, "channels");
	lua_getfield(luax, -1, channel);
	if (lua_isnil(luax, -1)) {
		lua_pop(luax, 1);
		lua_newtable(luax);
		lua_newtable(luax);
		lua_setfield(luax, -2, "queue");
		lua_setfield(luax, -2, channel);
		lua_getfield(luax, -1, channel);
	}
	lua_remove(luax, -2); // remove channels from stack
}

static int ll_push(lua_State *from_lua, lua_State *to_lua, int index) {
	switch(lua_type(from_lua, index)) {
	case LUA_TBOOLEAN:
		lua_pushboolean(to_lua, lua_toboolean(from_lua, index));
		break;
	case LUA_TNUMBER:
		lua_pushnumber(to_lua, lua_tonumber(from_lua, index));
		break;
	case LUA_TSTRING: {
		size_t size;
		const char *p = lua_tolstring(from_lua, index, &size);
		lua_pushlstring(to_lua, p, size);
		break;
	}
	default:
		return -1;
	}
	return 0;
}

/*	equivalant lua code:
 *	function send(channel, ...)
 *		lock()
 *		local queue = channels[channel].queue
 *              for _,v in ipairs({...}) do
 *			table.insert(queue, #queue+1, v)
 *		end
 *		notify_queue(channels[channel].wait)
 *		unlock()
 *	end
 */
static int ll_send(lua_State *lua) {
	const char *channel = luaL_checkstring(lua, 1);
	proc *p = NULL;
	int i, n;

	pthread_mutex_lock(&kernel_access);

	get_channel_entry(channel);

	// append all strings to end of `.queue`
	lua_getfield(luax, -1, "queue");
	luaL_checktype(luax, -1, LUA_TTABLE);

	n = lua_gettop(lua);
	lua_createtable(luax, n-1, 0);
	for (i = 2; i <= n; i++) {
		if (ll_push(lua, luax, i) < 0) {
			pthread_mutex_unlock(&kernel_access);
			luaL_error(lua, "%s only booleans, numbers, "
				"and strings supported", channel);
		}
		lua_rawseti(luax, -2, lua_objlen(luax, -2) + 1);
	}
	lua_rawseti(luax, -2, lua_objlen(luax, -2) + 1);
	lua_pop(luax, 1);

	// if `channels[channel].wait` the signal condition
	lua_getfield(luax, -1, "wait");
	if (!lua_isnil(luax, -1))
		p = (proc *)lua_touserdata(luax, -1);

	// clean luax stack
	lua_settop(luax, 0);

	// signal waiting receiver
	if (p != NULL)
		pthread_cond_signal(&p->cond);

	pthread_mutex_unlock(&kernel_access);
	return 0;
}

/*	equivalent lua code:
 *	function receive(channel, wait_time)
 *		if #channels[channel].queue == 0 then
 *			wait_queue(wait_time)
 *		end
 *		local new = {}
 *		lock()
 *		for _,v in ipairs(channels[channel].queue) do
 *			table.insert(new, v)
 *		end
 *		channels[channel].queue = {}
 *		unlock()
 *		return new
 *	end
 */
static int ll_receive(lua_State *lua) {
	proc *p = get_self(lua);
	const char *channel = luaL_checkstring(lua, 1);
	double d = luaL_checknumber(lua, 2);
	int n, m, i, j;

	pthread_mutex_lock(&kernel_access);

	get_channel_entry(channel);

	// if `channels[channel].wait ~= nil`, error (only one allowed)
	lua_getfield(luax, -1, "wait");
	if (!lua_isnil(luax, -1)) {
		lua_pop(luax, 2);
		pthread_mutex_unlock(&kernel_access);
		luaL_error(lua, "thread already waiting on %s", channel);
	}
	lua_pop(luax, 1); // remove nil from stack

	// get `#queue`, if zero, wait for condition timeout seconds
	lua_getfield(luax, -1, "queue");
	if (lua_objlen(luax, -1) < 1 && d > 0.0) {
		struct timespec ts[1];
		int sec = (int)d; // integer seconds of timeout
		lua_pop(luax, 1);

		// add `channels[channel].wait` so any `send(channel,...)`
		// will signal this thread that `.queue` data is avaliable
		lua_pushlightuserdata(luax, (void *)p);
		lua_setfield(luax, -2, "wait");
		// remove .queue from luax to empty stack
		lua_pop(luax, 1);

		// setup timeout which is abstime for `pthread_cond_timedwait`
		clock_gettime(CLOCK_REALTIME, ts);
		// fractional time and adjust `tv_nsec`/`tv_sec` to valid range
		d -= sec; // remove integer part
		ts->tv_nsec += d * 1e9;
		if (ts->tv_nsec >= 1000000000) {
			ts->tv_sec++;
			ts->tv_nsec -= 1000000000;
		}
		// add integral time to `tv_sec`
		ts->tv_sec += sec;

		pthread_cond_timedwait(&p->cond, &kernel_access, ts);

		// put `channels[channel]` back on stack
		get_channel_entry(channel);
		lua_getfield(luax, -1, "queue");
	}

	// move all entries from `.queue`(`luax`) to stack(`lua`)
	//lua_settop(lua, 1);
	n = lua_objlen(luax, -1);
	lua_createtable(lua, n, 0);
	for (i = 1; i <= n; i++) {
		lua_rawgeti(luax, -1, i);
		m = lua_objlen(luax, -1);

		lua_createtable(lua, m, 0);
		for (j = 1; j <= m; j++) {
			lua_rawgeti(luax, -1, j);
			if (ll_push(luax, lua, -1) < 0) {
				pthread_mutex_unlock(&kernel_access);
				luaL_error(lua, "%s only booleans, numbers, "
					"and strings supported", channel);
			}
			lua_pop(luax, 1);
			lua_rawseti(lua, -2, j);
		}
		lua_rawseti(lua, -2, lua_objlen(lua, -2) + 1);

		lua_pop(luax, 1);
	}
	lua_pop(luax, 1);

	// clear `channels[channel].queue`
	lua_newtable(luax);
	lua_setfield(luax, -2, "queue");

	// clear `channels[channel].wait`
	lua_pushnil(luax);
	lua_setfield(luax, -2, "wait");

	lua_settop(luax, 0);

	pthread_mutex_unlock(&kernel_access);
	return 1;
}

/* lua psuedo code:
 *	function queue_size(channel)
 *		local result
 *		lock()
 *		if channels[channel] == nil then
 *			result = 0
 *		else
 *			result = #channels[channel].queue
 *		end
 *		unlock()
 *		return result
 *	end
 */

static void *ll_thread(void *arg) {
	lua_State *lua = (lua_State *)arg;
	luaL_openlibs(lua);
	luaopen_threading(lua);
	if (lua_pcall(lua, lua_gettop(lua)-1, 0, 0) != 0)
		fprintf(stderr, "thread error: %s\n", lua_tostring(lua, -1));
	pthread_cond_destroy(&get_self(lua)->cond);
	lua_close(lua);
	pthread_exit(NULL);
	return NULL;
}

typedef struct chunk_move {
	luaL_Buffer b[1];
	const char *chunk;
	size_t size;
} chunk_move;

static int chunk_writer(lua_State *lua, const void *p, size_t sz, void *ud) {
	chunk_move *cm = (chunk_move *)ud;
	luaL_addlstring(cm->b, p, sz);
	return 0;
}

static const char *chunk_reader(lua_State *lua, void *ud, size_t *size) {
	chunk_move *cm = (chunk_move *)ud;
	*size = cm->size;
	return cm->chunk;
}

static int ll_start(lua_State *lua) {
	pthread_t thread;
	int i, n;
	chunk_move cm[1];
	/*
	size_t size; const char *chunk = luaL_checklstring(lua, 1, &size);
	*/
	lua_State *new_lua = luaL_newstate();
	if (new_lua == NULL)
		luaL_error(lua, "unable to create new state");

	n = lua_gettop(lua);
	for (i = 2; i <= n; i++) { // all but function
		ll_push(lua, new_lua, i);
	}
	lua_pushvalue(lua, 1);

	luaL_buffinit(new_lua, cm->b);
	if (lua_dump(lua, chunk_writer, cm) != 0) {
		luaL_error(lua, "unable to dump function: %d",
			lua_tostring(new_lua, -1));
	}
	luaL_pushresult(cm->b);
	cm->chunk = luaL_checklstring(new_lua, -1, &cm->size);

	if (lua_load(new_lua, chunk_reader, cm, "threading.start") != 0) {
		luaL_error(lua, "error starting thread: %s",
			lua_tostring(new_lua, -1));
	}

	lua_remove(new_lua, -2); // remove dumped string
	lua_insert(new_lua, 1); // move function to bottom of stack

	/*
	if (luaL_loadbuffer(new_lua, chunk, size, "start_thread") != 0) {
		luaL_error(lua, "error starting thread: %s",
			lua_tostring(new_lua, -1));
	}
	*/

	if (pthread_create(&thread, NULL, ll_thread, new_lua) != 0)
		luaL_error(lua, "unable to create new thread");

	pthread_detach(thread);
	return 0;
}

static int ll_exit(lua_State *lua) {
	pthread_exit(NULL);
	return 0;
}

static const struct luaL_Reg ll_funcs[] = {
	{ "start", 	ll_start },
	{ "send", 	ll_send },
	{ "receive",	ll_receive },
	{ "exit",	ll_exit },
	{ NULL,		NULL },
};

int luaopen_threading(lua_State *lua) {
	proc *self = (proc *)lua_newuserdata(lua, sizeof(proc));
	lua_setfield(lua, LUA_REGISTRYINDEX, "_SELF");
	pthread_mutex_lock(&kernel_access);
	if (luax == NULL) {
		luax = luaL_newstate();
		lua_createtable(luax, 0, 32); // allow for 32 channels
		lua_setfield(luax, LUA_GLOBALSINDEX, "channels");
	}
	pthread_mutex_unlock(&kernel_access);
	self->lua = lua;
	pthread_cond_init(&self->cond, NULL);
	luaL_register(lua, "threading", ll_funcs);
	return 1;
}

