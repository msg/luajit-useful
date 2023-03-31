#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <time.h>
#define LUA_COMPAT_ALL
#include <luaconf.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

// #include "threading.h"

#if 0
#define MODULE luaopen_threading
#else
#define MODULE luaopen_useful_threadingc
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
	if (top == 0)
		printf("<empty>");
        for (i = 1; i <= top; i++) {
                int t = lua_type(lua, i);
		printf("(%d)", i);
                switch(t) {
                case LUA_TSTRING: {
			size_t size;
			const char *p;
			p = lua_tolstring(lua, i, &size); // [-0 +0 m]
			if (*p == 0x1b)
				printf("s:code(%ld)'...' ", size);
			else
				printf("s:(%ld)'%s' ", size, p);
                        break;
		}
                case LUA_TBOOLEAN:
                        printf("b:%s ",
				(lua_toboolean(lua, i) ?  "true" : "false"));
                        break;
                case LUA_TNUMBER:
                        printf("n:%g ", lua_tonumber(lua, i));
                        break;
                case LUA_TTABLE:
                        printf("t: ");
                        break;
                case LUA_TNIL:
                        printf("0: ");
                        break;
                case LUA_TFUNCTION:
                        printf("f: ");
                        break;
                case LUA_TLIGHTUSERDATA:
                        printf("l:%p ", lua_touserdata(lua, i));
                        break;
                default :
                        printf("u:%d'%s' ", t, lua_typename(lua, t));
                        break;
                }
        }
        printf("\n");
}

static proc *get_self(lua_State *lua) {
	lua_getfield(lua, LUA_REGISTRYINDEX, "_SELF");		// [-0 +1 e ]
	proc *p = (proc *)lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	return p;
}

enum { IGNORE_ERROR, RAISE_ERROR };

static manager *get_manager(lua_State *lua, int handle_error) {
	manager *man;
	lua_getfield(lua, LUA_REGISTRYINDEX, "_MANAGER");	// [-0 +1 e]
	man = (manager *)lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	if (handle_error == RAISE_ERROR && man == NULL)
		luaL_error(lua, "manager NULL");
	return man;
}

static void migrate_paths(lua_State *from, lua_State *to) {
	lua_getglobal(from, "package");
	lua_getfield(from, -1, "path");
	lua_getfield(from, -2, "cpath");

	lua_getglobal(to, "package");
	lua_pushstring(to, lua_tostring(from, -2));
	lua_setfield(to, -2, "path");
	lua_pushstring(to, lua_tostring(from, -1));
	lua_setfield(to, -2, "cpath");
	lua_pop(to, 1);

	lua_pop(from, 3);
}

static void push_value(lua_State *to_lua, lua_State *from_lua,
		int index, lua_State *err_lua);

static void push_table(lua_State *to_lua, lua_State *from_lua,
		int index, lua_State *err_lua) {
	if (index < 0) /* index assumed to be positive for lua_next() */
		index = lua_gettop(from_lua) + index + 1;
	lua_newtable(to_lua);					// [-0 +1 m]
	lua_pushnil(from_lua); /* first key */
	while (lua_next(from_lua, index) != 0) {
		push_value(to_lua, from_lua, -2, err_lua);	// [-0 +0 e]
		push_value(to_lua, from_lua, -1, err_lua);	// [-0 +0 e]
		lua_settable(to_lua, -3);			// [-2 +0 e]
		lua_pop(from_lua, 1); // remove value
	}
	// from_lua [-0 +0 e], to_lua [-0 +1 e]
}

static void push_value(lua_State *to_lua, lua_State *from_lua,
		int index, lua_State *err_lua) {
	int type = lua_type(from_lua, index);
	switch(type) {
	case LUA_TNIL:
		lua_pushnil(to_lua);
		break;
	case LUA_TBOOLEAN:
		lua_pushboolean(to_lua, lua_toboolean(from_lua, index));
		break;
	case LUA_TNUMBER:
		lua_pushnumber(to_lua, lua_tonumber(from_lua, index));
		break;
	case LUA_TSTRING: {
		size_t size;
		const char *p;
		p = lua_tolstring(from_lua, index, &size);	// [-0 +0 m]
		lua_pushlstring(to_lua, p, size);		// [-0 +0 m]
		break;
	}
	case LUA_TTABLE:
		push_table(to_lua, from_lua, index, err_lua);	// [-? +? e]
		break;
	case LUA_TLIGHTUSERDATA: {
		void *p = lua_touserdata(from_lua, index);
		lua_pushlightuserdata(to_lua, p);
		break;
	}
	default:
		luaL_error(from_lua, "only nil, booleans, numbers, "
				"strings and non-recurive tables "
				"supported got type %d", type);	// [-0 +1 m]
	}
	// from_lua [-0 +0 e], to_lua [-0 +1 e]
}

static int push_stack(lua_State *to_lua, lua_State *from_lua,
		int start, lua_State *err_lua) {
	int i, n = lua_gettop(from_lua);
	for (i = start; i <= n; i++) {
		push_value(to_lua, from_lua, i, err_lua);	// [-0 +1 e]
	}
	// from_lua [-0 +0 e], to_lua [-0 +(n-start+1) e]
	return n - start + 1;
}

typedef struct chunk_move {
	luaL_Buffer buf[1];
	const char *chunk;
	size_t size;
} chunk_move;

static int chunk_writer(lua_State *lua, const void *p, size_t sz, void *ud) {
	(void)lua;
	chunk_move *cm = (chunk_move *)ud;
	luaL_addlstring(cm->buf, p, sz);			// [-0 +0 m]
	return 0;
}

static const char *chunk_reader(lua_State *lua, void *ud, size_t *size) {
	(void)lua;
	chunk_move *cm	= (chunk_move *)ud;
	*size		= cm->size;
	return cm->chunk;
}

static void load_code(lua_State *to_lua, lua_State *from_lua) {
	chunk_move cm[1];
	int rc;
	int n;

	lua_pushvalue(from_lua, 1); // push function on the top	// [-0 +1 m]
	n = lua_gettop(from_lua);
	luaL_buffinit(from_lua, cm->buf);
	rc = lua_dump(from_lua, chunk_writer, cm);		// [-0 +0 m]
	lua_remove(from_lua, n); // remove function on the top
	if (rc != 0)
		luaL_error(from_lua, "unable to dump function: %d",
			lua_tostring(from_lua, -1));
	luaL_pushresult(cm->buf);				// [1 +1 m]
	cm->chunk = luaL_checklstring(from_lua, -1, &cm->size);	// [-0 +0 m]

	lua_load(to_lua, chunk_reader, cm, "load_code");

	lua_pop(from_lua, 1); // remove buffer
}

static void add_traceback(lua_State *lua) {
	lua_getglobal(lua, "debug");				// [-0 +1 e]
	lua_getfield(lua, -1, "traceback");			// [-0 +1 e]
	lua_remove(lua, -2);
	lua_insert(lua, 1);
}

static void *thread_(void *arg) {
	lua_State *lua = (lua_State *)arg;
	int n = lua_gettop(lua);

	add_traceback(lua);					// [-0 +1 e]
	if (lua_pcall(lua, n-1, 0, 1) != 0) {
		fprintf(stderr, "thread error: %s\n", lua_tostring(lua, -1));
		fflush(stderr);
	}
	pthread_cond_destroy(&get_self(lua)->cond);
	lua_close(lua);

	return NULL;
}

static int start_(lua_State *lua) {
	lua_State *new_lua = luaL_newstate();
	if (new_lua == NULL)
		luaL_error(lua, "unable to create new state");

	manager *man = get_manager(lua, RAISE_ERROR);		// [-0 +0 e]

	luaL_openlibs(new_lua);

	migrate_paths(lua, new_lua);

	lua_pushlightuserdata(new_lua, man);			// [-0 +1 m]
	lua_setfield(new_lua, LUA_REGISTRYINDEX, "_MANAGER");	// [-0 +1 e]

	lua_cpcall(new_lua, MODULE, NULL);

	load_code(new_lua, lua);				// [-0 +1 e]

	push_stack(new_lua, lua, 2, lua);			// [-0 +? e]

	pthread_t thread;
	if (pthread_create(&thread, NULL, thread_, new_lua) != 0)
		luaL_error(lua, "unable to create new thread");
	pthread_detach(thread);

	return 0;
}

static int exit_(lua_State *lua) {
	(void)lua;
	pthread_exit(NULL);
	return 0;
}

static int setname_(lua_State *lua) {
	const char *name = luaL_checkstring(lua, 1);		// [-0 +0 e]
	pthread_setname_np(pthread_self(), name);
	return 0;
}

static int lock_(lua_State *lua) {
	manager *man = get_manager(lua, RAISE_ERROR);		// [-0 +0 e]
	pthread_mutex_lock(&man->mutex);
	return 0;
}

static int unlock_(lua_State *lua) {
	manager *man = get_manager(lua, RAISE_ERROR);		// [-0 +0 e]
	pthread_mutex_unlock(&man->mutex);
	return 0;
}

static int exec_(lua_State *lua) {
	manager *man = get_manager(lua, RAISE_ERROR);		// [-0 +0 e]
	int rc, n = lua_gettop(lua);

	load_code(man->lua, lua);				// [-0 +1 m]

	if ((n = push_stack(man->lua, lua, 2, lua)) < 0)	// [-0 +0 e]
		lua_error(lua);

	add_traceback(man->lua);				// [-0 +1 e]
	rc = lua_pcall(man->lua, n, LUA_MULTRET, 1);
	lua_remove(man->lua, 1); // remove error function

	if (rc != 0) // error, copy the error message.
		push_value(lua, man->lua, -1, lua);		// [-0 +1 m]
	else if ((n = push_stack(lua, man->lua, 1, lua)) < 0)	// [-0 +0 e]
		rc = -1;
	lua_settop(man->lua, 0);
	if (rc != 0)
		lua_error(lua);

	return n;
}

static pthread_cond_t *get_condition_locked(manager *man, const char *name) {
	lua_getfield(man->lua, LUA_REGISTRYINDEX, "conditions");// [-0 +1 e]
	lua_getfield(man->lua, -1, name);			// [-0 +1 e]
	pthread_cond_t *cond = (pthread_cond_t *)lua_touserdata(man->lua, -1);
	lua_pop(man->lua, 2);
	return cond;
}

static void set_condition_locked(manager *man, const char *name,
		pthread_cond_t *cond) {
	lua_getfield(man->lua, LUA_REGISTRYINDEX, "conditions");// [-0 +1 e]
	if (cond != NULL)
		lua_pushlightuserdata(man->lua, cond);		// [-0 +1 m]
	else
		lua_pushnil(man->lua);
	lua_setfield(man->lua, -2, name);			// [-1 +0 e]
	lua_pop(man->lua, 1);
}

static int signal_locked_(lua_State *lua) {
	manager *man		= get_manager(lua, RAISE_ERROR);// [-0 +0 e]
	const char *name	= luaL_checkstring(lua, 1);	// [-0 +0 e]
	pthread_cond_t *cond	= get_condition_locked(man, name);// [-0 +0 e]
	if (cond != NULL) {
		set_condition_locked(man, name, NULL);		// [-0 +0 e]
		pthread_cond_signal(cond);
	}
	return 0;
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

#define ts_cmp(a, b, CMP)			\
	(((a)->tv_sec == (b)->tv_sec)		\
	 ? ((a)->tv_nsec CMP (b)->tv_nsec)	\
	 : ((a)->tv_sec CMP (b)->tv_sec))

static int wait_locked_(lua_State *lua) {
	manager *man		= get_manager(lua, RAISE_ERROR);// [-0 +0 e]
	const char *name	= luaL_checkstring(lua, 1);	// [-0 +0 e]
	double timeout		= luaL_checknumber(lua, 2);	// [-0 +0 e]
	proc *self		= get_self(lua);
	pthread_cond_t *cond	= &self->cond;
	struct timespec ts[2];

	set_condition_locked(man, name, cond);			// [-0 +0 e]
	clock_gettime(CLOCK_REALTIME, ts);
	timespec_add(ts, timeout);

	while (cond != NULL) {
		pthread_cond_timedwait(cond, &man->mutex, ts);
		clock_gettime(CLOCK_REALTIME, ts + 1);
		if (ts_cmp(ts + 1, ts, >=))
			break;
		cond = get_condition_locked(man, name);		// [-0 +0 e]
	}
	set_condition_locked(man, name, NULL);
	return 0;
}

static const struct luaL_Reg ll_funcs[] = {
	{ "start", 	start_ },
	{ "setname",	setname_ },
	{ "exit",	exit_ },

	{ "lock",	lock_ },
	{ "unlock",	unlock_ },
	{ "signal",	signal_locked_ },	// man->lua
	{ "wait",	wait_locked_ },		// man->lua
	{ "exec",	exec_ },		// man->lua

	{ NULL,		NULL },
};

static int manager_mt_gc(lua_State *lua) {
	manager *man;
	lua_getfield(lua, LUA_REGISTRYINDEX, "_MANAGER");	// [-0 +1 e]
	man = (manager *)lua_touserdata(lua, -1);
	lua_close(man->lua);
	return 0;
}

static const struct luaL_Reg manager_mt_funcs[] = {
	{ "__gc",	manager_mt_gc },
	{ NULL,		NULL },
};

int MODULE(lua_State *lua) {
	luaL_register(lua, "useful.threadingc", ll_funcs);

	proc *self	= (proc *)lua_newuserdata(lua, sizeof(proc));
	lua_setfield(lua, LUA_REGISTRYINDEX, "_SELF");		// [-1 +0 e]
	self->lua	= lua;
	self->thread	= pthread_self();
	pthread_cond_init(&self->cond, NULL);

	manager *man = get_manager(lua, IGNORE_ERROR);		// [-0 +0 e]
	if (man == NULL) {
		man = (manager *)lua_newuserdata(lua, sizeof(manager));

		man->lua = luaL_newstate();
		pthread_mutex_init(&man->mutex, NULL);

		luaL_newmetatable(lua, "_MANAGER_MT");		// [-0 +1 m]
		luaL_register(lua, NULL, manager_mt_funcs);	// [-(0|1) +1 m]
		lua_setmetatable(lua, -2);
		lua_setfield(lua, LUA_REGISTRYINDEX, "_MANAGER");// [-1 +0 e]

		lua_newtable(man->lua);				// [-0 +1 m]
								// [-1 +0 e]
		lua_setfield(man->lua, LUA_REGISTRYINDEX, "conditions");

		luaL_openlibs(man->lua);
		lua_settop(man->lua, 0);

		migrate_paths(lua, man->lua);
	}
								// [-0 +1 m]
#if 0
	if (luaL_loadbuffer(lua, (const char *)luaJIT_BC_threading,
				luaJIT_BC_threading_SIZE, NULL))
		lua_error(lua);
	if (lua_pcall(lua, 0, 0, 0) != 0)
		fprintf(stderr, "error: %s\n", lua_tostring(lua, -1));
#endif

	return 1;
}

