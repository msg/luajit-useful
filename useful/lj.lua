--
-- u s e f u l / l u a j i t . l u a
--

local lj = { }

local ffi	= require('ffi')
local  C	=  ffi.C

local stdio	= require('useful.stdio')
local  sprintf	=  stdio.sprintf

ffi.cdef [[
	typedef ptrdiff_t		LUA_INTEGER;
	enum { LUA_IDSIZE		= 60 };
	typedef double			LUA_NUMBER;

	/* option for multiple returns in `lua_pcall' and `lua_call' */
	enum { LUA_MULTRET		= -1 };

	/*
	** pseudo-indices
	*/
	enum { LUA_REGISTRYINDEX	= -10000 };
	enum { LUA_ENVIRONINDEX		= -10001 };
	enum { LUA_GLOBALSINDEX		= -10002 };
	//auto lua_upvalueindex = (int i) => LUA_GLOBALSINDEX - i;

	/* thread status; 0 is OK */
	enum { LUA_YIELD		= 1 };
	enum { LUA_ERRRUN		= 2 };
	enum { LUA_ERRSYNTAX		= 3 };
	enum { LUA_ERRMEM		= 4 };
	enum { LUA_ERRERR		= 5 };

	typedef struct lua_State lua_State;

	typedef int (*lua_CFunction)(lua_State *L);

	/*
	** functions that read/write blocks when loading/dumping Lua chunks
	*/
	typedef const char * (*lua_Reader) (lua_State *L, void *ud, size_t *sz);

	typedef int (*lua_Writer) (lua_State *L,
				const void* p, size_t sz, void* ud);

	/*
	** prototype for memory-allocation functions
	*/
	typedef void * (*lua_Alloc) (void *ud,
				void *ptr, size_t osize, size_t nsize);

	/*
	** basic types
	*/
	enum { LUA_TNONE		= -1 };

	enum { LUA_TNIL			= 0 };
	enum { LUA_TBOOLEAN		= 1 };
	enum { LUA_TLIGHTUSERDATA	= 2 };
	enum { LUA_TNUMBER		= 3 };
	enum { LUA_TSTRING		= 4 };
	enum { LUA_TTABLE		= 5 };
	enum { LUA_TFUNCTION		= 6 };
	enum { LUA_TUSERDATA		= 7 };
	enum { LUA_TTHREAD		= 8 };
	enum { LUA_TPROTO		= 9 };
	enum { LUA_TCDATA		= 10 };

	/* minimum lua stack available to a c function */
	enum { LUA_MINSTACK		= 20 };

	/* type of numbers in lua */
	typedef LUA_NUMBER lua_Number;

	/* type for integer functions */
	typedef LUA_INTEGER lua_Integer;

	/*
	** state manipulation
	*/
	lua_State *lua_newstate(lua_Alloc f, void *ud);
	void       lua_close(lua_State *l);
	lua_State *lua_newthread(lua_State *l);

	lua_CFunction lua_atpanic(lua_State *l, lua_CFunction panicf);

	/*
	** basic stack manipulation
	*/
	int   lua_gettop(lua_State *L);
	void  lua_settop(lua_State *L, int idx);
	void  lua_pushvalue(lua_State *L, int idx);
	void  lua_remove(lua_State *L, int idx);
	void  lua_insert(lua_State *L, int idx);
	void  lua_replace(lua_State *L, int idx);
	int   lua_checkstack(lua_State *L, int sz);

	void  lua_xmove(lua_State *from, lua_State *to, int n);

	/*
	** access functions (stack -> C)
	*/
	int         lua_isnumber(lua_State *L, int idx);
	int         lua_isstring(lua_State *L, int idx);
	int         lua_iscfunction(lua_State *L, int idx);
	int         lua_isuserdata(lua_State *L, int idx);
	int         lua_type(lua_State *L, int idx);
	const char *lua_typename(lua_State *L, int tp);

	int         lua_equal(lua_State *L, int idx1, int idx2);
	int         lua_rawequal(lua_State *L, int idx1, int idx2);
	int         lua_lessthan(lua_State *L, int idx1, int idx2);

	lua_Number  lua_tonumber(lua_State *L, int idx);
	lua_Integer lua_tointeger(lua_State *L, int idx);
	int         lua_toboolean(lua_State *L, int idx);
	const char *lua_tolstring(lua_State *L, int idx, size_t *len);
	size_t      lua_objlen(lua_State *L, int idx);
	lua_CFunction lua_tocfunction(lua_State *L, int idx);
	void	   *lua_touserdata(lua_State *L, int idx);
	lua_State  *lua_tothread(lua_State *L, int idx);
	const void *lua_topointer(lua_State *L, int idx);

	/*
	** push functions (C -> stack)
	*/
	void  lua_pushnil(lua_State *L);
	void  lua_pushnumber(lua_State *L, lua_Number n);
	void  lua_pushinteger(lua_State *L, lua_Integer n);
	void  lua_pushlstring(lua_State *L, const char *s, size_t l);
	void  lua_pushstring(lua_State *L, const char *s);
	const char *lua_pushvfstring(lua_State *L, const char *fmt,
                                                      va_list argp);
	const char *lua_pushfstring(lua_State *L, const char *fmt, ...);
	void  lua_pushcclosure(lua_State *L, lua_CFunction fn, int n);
	void  lua_pushboolean(lua_State *L, int b);
	void  lua_pushlightuserdata(lua_State *L, void *p);
	int   lua_pushthread(lua_State *L);

	/*
	** get functions (Lua -> stack)
	*/
	void  lua_gettable(lua_State *L, int idx);
	void  lua_getfield(lua_State *L, int idx, const char *k);
	void  lua_rawget(lua_State *L, int idx);
	void  lua_rawgeti(lua_State *L, int idx, int n);
	void  lua_createtable(lua_State *L, int narr, int nrec);
	void *lua_newuserdata(lua_State *L, size_t sz);
	int   lua_getmetatable(lua_State *L, int objindex);
	void  lua_getfenv(lua_State *L, int idx);

	/*
	** set functions (stack -> Lua)
	*/
	void  lua_settable(lua_State *L, int idx);
	void  lua_setfield(lua_State *L, int idx, const char *k);
	void  lua_rawset(lua_State *L, int idx);
	void  lua_rawseti(lua_State *L, int idx, int n);
	int   lua_setmetatable(lua_State *L, int objindex);
	int   lua_setfenv(lua_State *L, int idx);

	/*
	** `load' and `call' functions (load and run Lua code)
	*/
	void  lua_call(lua_State *L, int nargs, int nresults);
	int   lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);
	int   lua_cpcall(lua_State *L, lua_CFunction func, void *ud);
	int   lua_load(lua_State *L, lua_Reader reader, void *dt,
                                        const char *chunkname);
	int   lua_dump(lua_State *L, lua_Writer writer, void *data);

	/*
	** coroutine functions
	*/
	int  lua_yield(lua_State *L, int nresults);
	int  lua_resume(lua_State *L, int narg);
	int  lua_status(lua_State *L);

	/*
	** garbage-collection function and options
	*/
	enum { LUA_GCSTOP		= 0 };
	enum { LUA_GCRESTART		= 1 };
	enum { LUA_GCCOLLECT		= 2 };
	enum { LUA_GCCOUNT		= 3 };
	enum { LUA_GCCOUNTB		= 4 };
	enum { LUA_GCSTEP		= 5 };
	enum { LUA_GCSETPAUSE		= 6 };
	enum { LUA_GCSETSTEPMUL		= 7 };
	enum { LUA_GCISRUNNING		= 9 };

	int lua_gc(lua_State *L, int what, int data);

	/*
	** miscellaneous functions
	*/
	int   lua_error(lua_State *L);
	int   lua_next(lua_State *L, int idx);
	void  lua_concat(lua_State *L, int n);
	lua_Alloc lua_getallocf(lua_State *L, void **ud);
	void lua_setallocf(lua_State *L, lua_Alloc f, void *ud);

	int (luaopen_bit)(lua_State *L);
	int (luaopen_ffi)(lua_State *L);
	int (luaopen_jit)(lua_State *L);
]]

--[[
** ===============================================================
** some useful macros
** ===============================================================
]]--

function lj.lua_pop(L, n)
	C.lua_settop(L, -n-1)
end

function lj.lua_newtable(L)
	C.lua_createtable(L, 0, 0)
end

function lj.lua_register(L, s, f)
	lj.lua_pushcfunction(L, f)
	lj.lua_setglobal(L, s)
end

function lj.lua_pushcfunction(L, f)
	return C.lua_pushcclosure(L, f, 0)
end

function lj.lua_strlen(L, i)
	return C.lua_objlen(L, i)
end

function lj.lua_isfunction(L, n)
	return C.lua_type(L, n) == C.LUA_TFUNCTION
end
function lj.lua_istable(L, n)
	return C.lua_type(L, n) == C.LUA_TTABLE
end
function lj.lua_islightuserdata(L, n)
	return C.lua_type(L, n) == C.LUA_TLIGHTUSERDATA
end
function lj.lua_isnil(L, n)
	return C.lua_type(L, n) == C.LUA_TNIL
end
function lj.lua_isboolean(L, n)
	return C.lua_type(L, n) == C.LUA_TBOOLEAN
end
function lj.lua_isthread(L, n)
	return C.lua_type(L, n) == C.LUA_TTHREAD
end
function lj.lua_isnone(L, n)
	return C.lua_type(L, n) == C.LUA_TNONE
end
function lj.lua_isnoneornil(L, n)
	return C.lua_type(L, n) <= 0
end

function lj.lua_pushliteral(L, s)
	C.lua_pushlstring(L, s, #s)
end

function lj.lua_setglobal(L, s)
	C.lua_setfield(L, C.LUA_GLOBALSINDEX, s)
end
function lj.lua_getglobal(L, s)
	C.lua_getfield(L, C.LUA_GLOBALSINDEX, s)
end

function lj.lua_tostring(L, i)
	return C.lua_tolstring(L, i, nil)
end

--[[
** compatibility macros and functions
]]--

function lj.lua_open()
	return C.luaL_newstate()
end

function lj.lua_getregistry(L)
	C.lua_pushvalue(L, C.LUA_REGISTRYINDEX)
end

function lj.lua_getgccount(L)
	return C.lua_gc(L, C.LUA_GCCOUNT, 0);
end

local s_ -- luacheck:ignore
s_ = [[
	/*
	#define lua_Chunkreader lua_Reader
	#define lua_Chunkwriter lua_Writer
	*/
]]

ffi.cdef [[
	/* hack */
	void lua_setlevel	(lua_State *from, lua_State *to);

	/*
	** ======================================================================
	** Debug API
	** =======================================================================
	*/

	/*
	** Event codes
	*/
	enum { LUA_HOOKCALL		= 0 };
	enum { LUA_HOOKRET		= 1 };
	enum { LUA_HOOKLINE		= 2 };
	enum { LUA_HOOKCOUNT		= 3 };
	enum { LUA_HOOKTAILRET		= 4 };

	/*
	** Event masks
	*/
	enum { LUA_MASKCALL		= 1 << LUA_HOOKCALL };
	enum { LUA_MASKRET		= 1 << LUA_HOOKRET };
	enum { LUA_MASKLINE		= 1 << LUA_HOOKLINE };
	enum { LUA_MASKCOUNT		= 1 << LUA_HOOKCOUNT };

	typedef struct lua_Debug lua_Debug;   /* activation record */

	/* Functions to be called by the debuger in specific events */
	typedef void (*lua_Hook) (lua_State *L, struct lua_Debug *ar);

	int lua_getstack (lua_State *L, int level, lua_Debug *ar);
	int lua_getinfo (lua_State *L, const char *what, lua_Debug *ar);
	const char *lua_getlocal (lua_State *L, const lua_Debug *ar, int n);
	const char *lua_setlocal (lua_State *L, const lua_Debug *ar, int n);
	const char *lua_getupvalue (lua_State *L, int funcindex, int n);
	const char *lua_setupvalue (lua_State *L, int funcindex, int n);
	int lua_sethook (lua_State *L, lua_Hook func, int mask, int count);
	lua_Hook lua_gethook (lua_State *L);
	int lua_gethookmask (lua_State *L);
	int lua_gethookcount (lua_State *L);

	/* From Lua 5.2. */
	void *lua_upvalueid (lua_State *L, int idx, int n);
	void lua_upvaluejoin (lua_State *L, int idx1, int n1, int idx2, int n2);
	int lua_loadx (lua_State *L, lua_Reader reader, void *dt,
			const char *chunkname, const char *mode);

	struct lua_Debug {
	int event;
	const char *name;	/* (n) */
	const char *namewhat;	/* (n) `global', `local', `field', `method' */
	const char *what;	/* (S) `Lua', `C', `main', `tail' */
	const char *source;	/* (S) */
	int currentline;	/* (l) */
	int nups;		/* (u) number of upvalues */
	int linedefined;	/* (S) */
	int lastlinedefined;	/* (S) */
	char short_src[LUA_IDSIZE]; /* (S) */
	/* private part */
	int i_ci;  /* active function */
	};
]]

s_ = [[
	//
	// l a u x l i b
	//
]]

function lj.luaL_getn(L, i)
	return C.lua_objlen(L, i)
end

function lj.luaL_estn(L, i, j) -- luacheck:ignore
	-- no op!
end

ffi.cdef [[
	/* extra error code for `luaL_load' */
	enum { LUA_ERRFILE = LUA_ERRERR + 1 };

	typedef struct luaL_Reg {
		const char *name;
		lua_CFunction func;
	} luaL_Reg;

	void luaL_openlib(lua_State *L, const char *libname,
                                const luaL_Reg *l, int nup);
	void luaL_register(lua_State *L, const char *libname,
                                const luaL_Reg *l);
	int luaL_getmetafield(lua_State *L, int obj, const char *e);
	int luaL_callmeta(lua_State *L, int obj, const char *e);
	int luaL_typerror(lua_State *L, int narg, const char *tname);
	int luaL_argerror(lua_State *L, int numarg, const char *extramsg);
	const char *luaL_checklstring(lua_State *L, int numArg,
				size_t *l);
	const char *luaL_optlstring(lua_State *L, int numArg,
				const char *def, size_t *l);
	lua_Number luaL_checknumber(lua_State *L, int numArg);
	lua_Number luaL_optnumber(lua_State *L, int nArg,
				lua_Number def);

	lua_Integer luaL_checkinteger(lua_State *L, int numArg);
	lua_Integer luaL_optinteger(lua_State *L, int nArg,
                                          lua_Integer def);

	void luaL_checkstack(lua_State *L, int sz, const char *msg);
	void luaL_checktype(lua_State *L, int narg, int t);
	void luaL_checkany(lua_State *L, int narg);

	int   luaL_newmetatable(lua_State *L, const char *tname);
	void *luaL_checkudata(lua_State *L, int ud, const char *tname);

	void luaL_where(lua_State *L, int lvl);
	int luaL_error(lua_State *L, const char *fmt, ...);

	int luaL_checkoption(lua_State *L, int narg, const char *def,
				const char *lst[]);

	int luaL_ref(lua_State *L, int t);
	void luaL_unref(lua_State *L, int t, int ref_);

	int luaL_loadfile(lua_State *L, const char *filename);
	int luaL_loadbuffer(lua_State *L, const char *buff, size_t sz,
				const char *name);
	int luaL_loadstring(lua_State *L, const char *s);

	lua_State *luaL_newstate();


	const char *luaL_gsub(lua_State *L, const char *s,
				const char *p, const char *r);

	const char *luaL_findtable(lua_State *L, int idx,
				const char *fname, int szhint);

	/* From Lua 5.2. */
	int luaL_fileresult(lua_State *L, int stat, const char *fname);
	int luaL_execresult(lua_State *L, int stat);
	int luaL_loadfilex(lua_State *L, const char *filename,
				const char *mode);
	int luaL_loadbufferx(lua_State *L, const char *buff, size_t sz,
				const char *name, const char *mode);
	void luaL_traceback(lua_State *L, lua_State *L1,
				const char *msg, int level);
]]

s_ = [[
	/*
	** ===============================================================
	** some useful macros
	** ===============================================================
	*/
]]

function lj.luaL_argcheck(L, cond, numarg, extramsg)
	if cond then
		C.luaL_argerror(L, numarg, extramsg)
	end
end

function lj.luaL_checkstring(L, n)
	return C.luaL_checklstring(L, n, nil)
end

function lj.luaL_optstring(L, n, d)
	return C.luaL_optlstring(L, n, d, nil)
end

lj.luaL_checkint	= C.luaL_checkinteger
lj.luaL_optint		= C.luaL_optinteger
lj.luaL_checklong	= C.luaL_checkinteger
lj.luaL_optlong		= C.luaL_optinteger

function lj.luaL_typename(L, i)
	return C.lua_typename(L, C.lua_type(L, i))
end

function lj.luaL_dofile(L, fn)
	local rc = C.luaL_loadfile(L, fn)
	if rc == 0 then
		rc = C.lua_pcall(L, 0, C.LUA_MULTRET, 0)
	end
	return rc
end

function lj.luaL_dostring(L, s) -- luacheck:ignore
	local rc = C.luaL_loadstring(L, s)
	if rc == 0 then
		rc = C.lua_pcall(L, 0, C.LUA_MULTRET, 0)
	end
	return rc
end

function lj.luaLopt(L, f, n, d)
	if C.lua_isnoneornil(L, n) then
		return d
	else
		return f(L, n)
	end
end

s_ = [[
	/*
	** {======================================================
	** Generic Buffer manipulation
	** =======================================================
	*/
	enum LUAL_BUFFERSIZE = 8192;

	struct luaL_Buffer {
		char *p; /* current position in buffer */
		int lvl; /* number of strings in the stack (level) */
		lua_State *L;
		char[LUAL_BUFFERSIZE] buffer;
	};

	void luaL_addchar(luaL_Buffer *B, char c) {
		if(B.p < (cast(char *)B.buffer + LUAL_BUFFERSIZE))
			luaL_prepbuffer(B);
		*(B.p++) = c;
	}

	void luaL_addsize(luaL_Buffer *B, int n) {
		B.p += n;
	}

	void luaL_buffinit(lua_State *L, luaL_Buffer *B);
	char *luaL_prepbuffer(luaL_Buffer *B);
	void luaL_addlstring(luaL_Buffer *B, const char *s, size_t l);
	void luaL_addstring(luaL_Buffer *B, const char *s);
	void luaL_addvalue(luaL_Buffer *B);
	void luaL_pushresult(luaL_Buffer *B);

	/* }====================================================== */

	/* compatibility with ref system */

	/* pre-defined references */
	enum LUA_NOREF		= -2;
	enum LUA_REFNIL		= -1;

	int lua_ref(lua_State *L, bool lock) {
		if(lock)
			return luaL_ref(L, LUA_REGISTRYINDEX);
		else {
			lua_pushstring(L,
				"unlocked references are obsolete");
			lua_error(L);
			return 0;
		}
	}

	void lua_unref(lua_State *L, int ref_) {
		luaL_unref(L, LUA_REGISTRYINDEX, ref_);
	}

	void lua_getref(lua_State *L, int ref_) {
		lua_rawgeti(L, LUA_REGISTRYINDEX, ref_);
	}

	/*
	#define luaL_reg luaL_Reg
	*/
]]

ffi.cdef [[
	//
	// l u a l i b s
	//
	int luaopen_base(lua_State *L);
	int luaopen_math(lua_State *L);
	int luaopen_string(lua_State *L);
	int luaopen_table(lua_State *L);
	int luaopen_io(lua_State *L);
	int luaopen_os(lua_State *L);
	int luaopen_package(lua_State *L);
	int luaopen_debug(lua_State *L);
	int luaopen_bit(lua_State *L);
	int luaopen_jit(lua_State *L);
	int luaopen_ffi(lua_State *L);

	void luaL_openlibs(lua_State *L);
]]

function lj.lj_tostring(L, i)
	local sp = C.lua_tolstring(L, i, nil)
	if sp ~= nil then
		sp = ffi.string(sp)
	end
	return sp
end

function lj.lj_typename(L, i)
	local sp = lj.luaL_typename(L, i)
	if sp ~= nil then
		sp = ffi.string(sp)
	end
	return sp
end

function lj.stack_dump(lua)
	local top = lj.lua_gettop(lua)
	local s = sprintf('stack %d: ', top)
	if top == 0 then
		s = s..'<empty>'
	end
	for i=1,top do
		s = s..sprintf('(%d)', i)
		local t = lj.lua_type(lua, i)
		if t == lj.LUA_TTABLE then		s = s..sprintf('t:')
		elseif t == lj.LUA_TNIL then		s = s..sprintf('0:')
		elseif t == lj.LUA_TFUNCTION then	s = s..sprintf('f:')
		elseif t == lj.LUA_TSTRING then
			s = s..sprintf("s:'%s'", lj.lj_tostring(lua, i))
		elseif t == lj.LUA_TBOOLEAN then
			s = s..sprintf('b:%s', lj.lua_toboolean(lua, i) and
					'true' or 'false')
		elseif t == lj.LUA_TNUMBER then
			s = s..sprintf('n:%g', lj.lua_tonumber(lua, i))
		else
			s = s..sprintf('u(%d):%s', t, lj.lj_typename(lua, i))
			s = s..sprintf(' %s', lj.lua_topointer(lua, i))
		end
		s = s..sprintf('  ')
	end
	return s
end

local pc = pcall
setmetatable(lj, {
	__index = function(t, k)
		local ok,v = pc(function()
			return C[k]
		end)
		if ok == true then
			return v
		else
			return t[k]
		end
	end,
})

return lj
