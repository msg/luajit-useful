#include <pthread.h>
#include <time.h>
#include <string.h>
#define LUA_COMPAT_ALL
#include <luaconf.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

typedef struct proc {
	lua_State *lua;
	pthread_t thread;
	pthread_cond_t cond;
} proc;

typedef struct manager {
	lua_State *lua;
	pthread_mutex_t mutex;
	proc *prev, *next;
} manager;

int luaopen_useful_threading(lua_State *lua);

static proc *get_self(lua_State *lua) {
	lua_getfield(lua, LUA_REGISTRYINDEX, "_SELF");
	proc *p = (proc *)lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	return p;
}

enum { IGNORE_ERROR, RAISE_ERROR };

static manager *get_manager(lua_State *lua, int handle_error) {
	manager *man;
	lua_getfield(lua, LUA_REGISTRYINDEX, "_MANAGER");
	man = (manager *)lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	if (handle_error == RAISE_ERROR && man == NULL) {
		luaL_error(lua, "manager NULL");
	}
	return man;
}

static void push_channel_and_queue(lua_State *lua, const char *channel) {
	// put `channels[channel]` on stack
	lua_getfield(lua, LUA_GLOBALSINDEX, "channels");
	lua_getfield(lua, -1, channel);
	if (lua_isnil(lua, -1)) {
		lua_pop(lua, 1);		// remove nil
		lua_newtable(lua);		// channel table
		lua_newtable(lua);		// queue table
		lua_setfield(lua, -2, "queue");	// set channel.queue
		lua_setfield(lua, -2, channel);	// set channels[channel]
		lua_getfield(lua, -1, channel);	//   get it back
	}
	lua_remove(lua, -2);		// remove 'channels' from stack
	lua_getfield(lua, -1, "queue"); // push queue also
}

static int move_value(lua_State *to_lua, lua_State *from_lua, int index) {
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
		lua_settop(from_lua, 0);
		lua_pushstring(from_lua, "only booleans, numbers, and strings "
				"supported");
		return -1;
	}
	return 0;
}

static int stack_to_new_table(lua_State *to_lua, lua_State *from_lua) {
	int i, rc;
	int n = lua_gettop(from_lua);
	lua_createtable(to_lua, 0, 0);
	for (i = 2; i <= n; i++) {
		rc = move_value(to_lua, from_lua, i);
		if (rc < 0)
			return rc;
		lua_rawseti(to_lua, -2, lua_objlen(to_lua, -2) + 1);
	}
	return rc;
}

static void notify_receivers(manager *man) {
	// if `channels[channel].wait` the signal condition
	lua_getfield(man->lua, -1, "wait");
	if (!lua_isnil(man->lua, -1)) {
		proc *p = (proc *)lua_touserdata(man->lua, -1);
		pthread_cond_signal(&p->cond);
	}
}

static int ll_send(lua_State *lua) {
	manager *man = get_manager(lua, RAISE_ERROR);
	const char *channel = luaL_checkstring(lua, 1);
	int i, rc;

	pthread_mutex_lock(&man->mutex);

	push_channel_and_queue(man->lua, channel);

	rc = stack_to_new_table(man->lua, lua);
	if (rc == 0) // append table to channels[channel].queue table
		lua_rawseti(man->lua, -2, lua_objlen(man->lua, -2) + 1);

	notify_receivers(man);

	lua_settop(man->lua, 0); // clean man->lua stack

	pthread_mutex_unlock(&man->mutex);

	if (rc < 0)
		lua_error(lua);

	return 0;
}

static int move_itable(lua_State *to_lua, lua_State *from_lua) {
	int i, rc;

	int n = lua_objlen(from_lua, -1);
	for (i = 1; i <= n; i++) {
		lua_rawgeti(from_lua, -1, i);
		rc = move_value(to_lua, from_lua, -1);
		lua_pop(from_lua, 1);
		if (rc < 0)
			return rc;
		lua_rawseti(to_lua, -2, lua_objlen(to_lua, -2) + 1);
	}
	return rc;
}

static void timespec_add(struct timespec *ts, double dt) {
	int iseconds = (int)dt;
	dt -= iseconds;
	dt *= 1e9;
	ts->tv_nsec += dt;
	if (ts->tv_nsec >= 1000000000) {
		ts->tv_sec++;
		ts->tv_nsec -= 1000000000;
	}
	ts->tv_sec += iseconds;
}

static int wait_for_queue(manager *man, proc *p, double timeout) {
	struct timespec ts[1];
	int seconds = (int)timeout;

	lua_pushlightuserdata(man->lua, (void *)p);
	lua_setfield(man->lua, -2, "wait");
	lua_settop(man->lua, 0); // clear stack

	clock_gettime(CLOCK_REALTIME, ts);
	timespec_add(ts, timeout);

	pthread_cond_timedwait(&p->cond, &man->mutex, ts);
}

static int ll_receive(lua_State *lua) {
	proc *p = get_self(lua);
	manager *man = get_manager(lua, RAISE_ERROR);
	const char *channel = luaL_checkstring(lua, 1);
	double timeout = luaL_checknumber(lua, 2);
	int i, n, sz;

	pthread_mutex_lock(&man->mutex);

	push_channel_and_queue(man->lua, channel);

	// wait for timeout seconds for a message
	if (lua_objlen(man->lua, -1) < 1 && timeout > 0.0) {
		wait_for_queue(man, p, timeout);

		// wait_for_queue clears stack
		push_channel_and_queue(man->lua, channel);

		// clear wait
		lua_pushnil(man->lua);
		lua_setfield(man->lua, -3, "wait");
	}

	// man->lua stack: queue, channel
	lua_createtable(lua, 0, 0);
	// lua stack: new_table
	if (lua_objlen(man->lua, -1) > 0) {
		lua_rawgeti(man->lua, -1, 1);
		// man->lua stack: queue[1], queue, channel

		// move man->lua queue[2..#queue] to queue[1..#queue-1]

		n = lua_objlen(man->lua, -2);
		for (i = 1; i <= n; i++) {
			// lua_rawgeti > n will push nil which is what we want
			lua_rawgeti(man->lua, -2, i+1);
			lua_rawseti(man->lua, -3, i);
		}

		lua_createtable(lua, 1, 0);
		move_itable(lua, man->lua);
		lua_rawseti(lua, -2, 1);
	}

	lua_settop(man->lua, 0);

	pthread_mutex_unlock(&man->mutex);

	return 1;
}

static void *ll_thread(void *arg) {
	lua_State *lua = (lua_State *)arg;
	int n = lua_gettop(lua);
	luaL_openlibs(lua);
	lua_cpcall(lua, luaopen_useful_threading, NULL);
	if (lua_pcall(lua, n-1, 0, 0) != 0)
		fprintf(stderr, "thread error: %s\n", lua_tostring(lua, -1));
	pthread_cond_destroy(&get_self(lua)->cond);
	lua_close(lua);
	return NULL;
}

typedef struct chunk_move {
	luaL_Buffer buf[1];
	const char *chunk;
	size_t size;
} chunk_move;

static int chunk_writer(lua_State *lua, const void *p, size_t sz, void *ud) {
	chunk_move *cm = (chunk_move *)ud;
	luaL_addlstring(cm->buf, p, sz);
	return 0;
}

static const char *chunk_reader(lua_State *lua, void *ud, size_t *size) {
	chunk_move *cm = (chunk_move *)ud;
	*size = cm->size;
	return cm->chunk;
}

static void load_function(lua_State *to_lua, lua_State *from_lua) {
	chunk_move cm[1];

	luaL_buffinit(to_lua, cm->buf);
	if (lua_dump(from_lua, chunk_writer, cm) != 0) {
		luaL_error(from_lua, "unable to dump function: %d",
			lua_tostring(from_lua, -1));
	}
	luaL_pushresult(cm->buf);
	cm->chunk = luaL_checklstring(to_lua, -1, &cm->size);

	if (lua_load(to_lua, chunk_reader, cm, "threading.start") != 0) {
		luaL_error(from_lua, "error loading thread: %s",
			lua_tostring(from_lua, -1));
	}

	lua_remove(to_lua, -2); // remove dumped string
	lua_insert(to_lua, 1); // move function to bottom of stack
}

static int ll_start(lua_State *lua) {
	int i, n;
	lua_State *new_lua;

	new_lua = luaL_newstate();
	if (new_lua == NULL)
		luaL_error(lua, "unable to create new state");

	manager *man = get_manager(lua, RAISE_ERROR);
	lua_pushlightuserdata(new_lua, man);
	lua_setfield(new_lua, LUA_REGISTRYINDEX, "_MANAGER");

	n = lua_gettop(lua);
	for (i = 2; i <= n; i++) { // all but function
		move_value(new_lua, lua, i);
	}
	lua_pushvalue(lua, 1); // push function on the top

	load_function(new_lua, lua);

	pthread_t thread;
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

static int manager_mt_gc(lua_State *lua) {
	manager *man;
	lua_getfield(lua, LUA_REGISTRYINDEX, "_MANAGER");
	man = (manager *)lua_touserdata(lua, -1);
	lua_close(man->lua);
	return 0;
}

static const struct luaL_Reg manager_mt_funcs[] = {
	{ "__gc",	manager_mt_gc },
	{ NULL,		NULL },
};

int luaopen_useful_threading(lua_State *lua) {
	proc *self = (proc *)lua_newuserdata(lua, sizeof(proc));
	lua_setfield(lua, LUA_REGISTRYINDEX, "_SELF");
	self->lua = lua;
	self->thread = pthread_self();
	pthread_cond_init(&self->cond, NULL);

	manager *man = get_manager(lua, IGNORE_ERROR);
	if (man == NULL) {
		man = (manager *)lua_newuserdata(lua, sizeof(manager));
		luaL_newmetatable(lua, "_MANAGER_MT");
		luaL_register(lua, NULL, manager_mt_funcs);
		lua_setmetatable(lua, -2);
		lua_setfield(lua, LUA_REGISTRYINDEX, "_MANAGER");
		man->lua = luaL_newstate();
		lua_createtable(man->lua, 0, 0);
		lua_setfield(man->lua, LUA_GLOBALSINDEX, "channels");
		luaL_openlibs(man->lua);
		pthread_mutex_init(&man->mutex, NULL);
	}

	luaL_register(lua, "useful.threading", ll_funcs);
	return 1;
}

