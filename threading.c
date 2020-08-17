#define _GNU_SOURCE
#include <pthread.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#define LUA_COMPAT_ALL
#include <luaconf.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define DEBUG(x, lua) \
	printf("%s: %d " x " ", __FILE__, __LINE__); stack_dump(lua)

#if 0
#define MODULE luaopen_threading
#else
#define MODULE luaopen_useful_threading
#endif
int MODULE(lua_State *lua);


typedef struct proc {
	lua_State *lua;
	pthread_t thread;
	pthread_cond_t cond;
} proc;

typedef struct manager {
	lua_State *lua;
	pthread_mutex_t mutex;
} manager;

void stack_dump(lua_State *lua) {
        // stack_dump doesn't lock, therefore lock before calling
        int i;
        int top = lua_gettop(lua);
        printf("stack %d: ", top);
        for (i = 1; i <= top; i++) {
                int t = lua_type(lua, i);
		printf("(%d)", i);
                switch(t) {
                case LUA_TSTRING:
                        printf("s:'%s'  ", lua_tostring(lua, i));
                        break;
                case LUA_TBOOLEAN:
                        printf("b: %s  ",
				(lua_toboolean(lua, i) ?  "true" : "false"));
                        break;
                case LUA_TNUMBER:
                        printf("n:%g  ", lua_tonumber(lua, i));
                        break;
                case LUA_TTABLE:
                        printf("t:  ");
                        break;
                case LUA_TNIL:
                        printf("0:  ");
                        break;
                case LUA_TFUNCTION:
                        printf("f:   ");
                        break;
                default :
                        printf("u:'%s'  ", lua_typename(lua, i));
                        break;
                }
        }
        printf("\n");
}

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

static int copy_table(lua_State *to_lua, lua_State *from_lua, int index);

static int copy_value(lua_State *to_lua, lua_State *from_lua, int index) {
	int type = lua_type(from_lua, index);
	switch(type) {
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
	case LUA_TTABLE:
		copy_table(to_lua, from_lua, index);
		break;
	default:
		lua_settop(from_lua, 0);
		lua_pushstring(from_lua, "only booleans, numbers, "
				"strings and non-recurive tables "
				"supported");
		return -1;
	}
	return 0;
}

static int copy_table(lua_State *to_lua, lua_State *from_lua, int index) {
	int to_top;
	lua_newtable(to_lua);
	to_top = lua_gettop(to_lua);
	lua_pushnil(from_lua); /* first key */
	while (lua_next(from_lua, index) != 0) {
		copy_value(to_lua, from_lua, -2);
		if (lua_type(from_lua, -1) == LUA_TTABLE)
			copy_table(to_lua, from_lua, lua_gettop(from_lua));
		else
			copy_value(to_lua, from_lua, -1);
		lua_settable(to_lua, to_top);
		lua_pop(from_lua, 1);
	}
	return 0;
}

static int stack_to_new_table(lua_State *to_lua, lua_State *from_lua) {
	int i, rc;
	int n = lua_gettop(from_lua);
	lua_createtable(to_lua, 0, 0);
	for (i = 2; i <= n; i++) {
		rc = copy_value(to_lua, from_lua, i);
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
	int rc;

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
		rc = copy_value(to_lua, from_lua, -1);
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

	lua_pushlightuserdata(man->lua, (void *)p);
	lua_setfield(man->lua, -2, "wait");
	lua_settop(man->lua, 0); // clear stack

	clock_gettime(CLOCK_REALTIME, ts);
	timespec_add(ts, timeout);

	pthread_cond_timedwait(&p->cond, &man->mutex, ts);

	return 0;
}

static int ll_receive(lua_State *lua) {
	proc *p = get_self(lua);
	manager *man = get_manager(lua, RAISE_ERROR);
	const char *channel = luaL_checkstring(lua, 1);
	double timeout = luaL_checknumber(lua, 2);
	int i, n;

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
		// i.e. table.remove(queue, 1)

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

	lua_getglobal(lua, "debug");
	lua_getfield(lua, -1, "traceback");
	lua_remove(lua, -2);
	lua_insert(lua, 1);

	if (lua_pcall(lua, n-1, 0, 1) != 0)
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
	(void)lua;
	chunk_move *cm = (chunk_move *)ud;
	luaL_addlstring(cm->buf, p, sz);
	return 0;
}

static const char *chunk_reader(lua_State *lua, void *ud, size_t *size) {
	(void)lua;
	chunk_move *cm = (chunk_move *)ud;
	*size = cm->size;
	return cm->chunk;
}

static void load_function(lua_State *to_lua, lua_State *from_lua) {
	chunk_move cm[1];

	if (lua_isstring(from_lua, -1)) {
		luaL_loadstring(to_lua, lua_tostring(from_lua, -1));
		lua_insert(to_lua, 1); // move function to bottom of stack
		return;
	}

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

	luaL_openlibs(new_lua);
	lua_cpcall(new_lua, MODULE, NULL);

	n = lua_gettop(lua);
	for (i = 2; i <= n; i++) { // all but function
		if (copy_value(new_lua, lua, i) < 0)
			lua_error(lua);
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
	(void)lua;
	pthread_exit(NULL);
	return 0;
}

static int ll_setname(lua_State *lua) {
	const char *name = luaL_checkstring(lua, 1);
	pthread_setname_np(pthread_self(), name);
	return 0;
}

static int ll_manager(lua_State *lua) {
	manager *man;
	if (lua_gettop(lua) > 0) {
		// set manager
		const char *p = lua_tostring(lua, -1);
		sscanf(p, "%p", (void **)&man);
		lua_pushlightuserdata(lua, man);
		lua_setfield(lua, LUA_REGISTRYINDEX, "_MANAGER");
		return 0;
	} else {
		// get manager
		char pointer[128];
		man = get_manager(lua, RAISE_ERROR);
		int l = sprintf(pointer, "%p", man);
		lua_pushlstring(lua, pointer, l);
		return 1;
	}
}

static int ll_get(lua_State *lua) {
	const char *name = luaL_optstring(lua, 1, NULL);
	manager *man = get_manager(lua, RAISE_ERROR);

	pthread_mutex_lock(&man->mutex);

	lua_getfield(man->lua, LUA_GLOBALSINDEX, "data");
	if (name != NULL) {
		lua_getfield(man->lua, -1, name);
		if (!lua_isnil(man->lua, 2))
			copy_value(lua, man->lua, 2);
		else
			lua_pushnil(lua);
	} else
		copy_value(lua, man->lua, 1);
	lua_settop(man->lua, 0);

	pthread_mutex_unlock(&man->mutex);
	return 1;
}

static int ll_set(lua_State *lua) {
	const char *name = luaL_checkstring(lua, 1);
	manager *man = get_manager(lua, RAISE_ERROR);

	pthread_mutex_lock(&man->mutex);

	lua_getfield(man->lua, LUA_GLOBALSINDEX, "data");
	if (copy_value(man->lua, lua, 2)) {
		copy_value(lua, man->lua, 1);
		// lua_error() calls longjmp() so mutex must be unlocked.
		pthread_mutex_unlock(&man->mutex);
		lua_error(lua);
	}
	lua_setfield(man->lua, 1, name);
	lua_settop(man->lua, 0);

	pthread_mutex_unlock(&man->mutex);
	return 0;
}

static const struct luaL_Reg ll_funcs[] = {
	{ "manager",	ll_manager },
	{ "start", 	ll_start },
	{ "setname",	ll_setname },
	{ "send", 	ll_send },
	{ "receive",	ll_receive },
	{ "set",	ll_set },
	{ "get",	ll_get },
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

int MODULE(lua_State *lua) {
	luaL_register(lua, "useful.threading", ll_funcs);

	proc *self = (proc *)lua_newuserdata(lua, sizeof(proc));
	lua_setfield(lua, LUA_REGISTRYINDEX, "_SELF");
	self->lua = lua;
	self->thread = pthread_self();
	pthread_cond_init(&self->cond, NULL);

	manager *man = get_manager(lua, IGNORE_ERROR);
	if (man == NULL) {
		man = (manager *)lua_newuserdata(lua, sizeof(manager));

		man->lua = luaL_newstate();
		pthread_mutex_init(&man->mutex, NULL);

		luaL_newmetatable(lua, "_MANAGER_MT");
		luaL_register(lua, NULL, manager_mt_funcs);
		lua_setmetatable(lua, -2);
		lua_setfield(lua, LUA_REGISTRYINDEX, "_MANAGER");

		lua_createtable(man->lua, 0, 0);
		lua_setfield(man->lua, LUA_GLOBALSINDEX, "channels");

		lua_createtable(man->lua, 0, 0);
		lua_setfield(man->lua, LUA_GLOBALSINDEX, "data");

		luaL_openlibs(man->lua);
	}

	return 1;
}

