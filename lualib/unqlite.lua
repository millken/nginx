local ffi = require "ffi"

local Lib = ffi.load("unqlite")

ffi.cdef[[
void free(void *ptr);

static const int UNQLITE_OK     = 0;

static const int SXRET_OK       = 0;      /* Not an error */
static const int SXERR_MEM      = -1;   /* Out of memory */
static const int SXERR_IO       = -2;   /* IO error */
static const int SXERR_EMPTY    = -3;   /* Empty field */
static const int SXERR_LOCKED   = -4;   /* Locked operation */
static const int SXERR_ORANGE   = -5;   /* Out of range value */
static const int SXERR_NOTFOUND = -6;   /* Item not found */
static const int SXERR_LIMIT    = -7;   /* Limit reached */
static const int SXERR_MORE     = -8;   /* Need more input */
static const int SXERR_INVALID  = -9;   /* Invalid parameter */
static const int SXERR_ABORT    = -10;  /* User callback request an operation abort */
static const int SXERR_EXISTS   = -11;  /* Item exists */
static const int SXERR_SYNTAX   = -12;  /* Syntax error */
static const int SXERR_UNKNOWN  = -13;  /* Unknown error */
static const int SXERR_BUSY     = -14;  /* Busy operation */
static const int SXERR_OVERFLOW = -15;  /* Stack or buffer overflow */
static const int SXERR_WILLBLOCK = -16; /* Operation will block */
static const int SXERR_NOTIMPLEMENTED = -17; /* Operation not implemented */
static const int SXERR_EOF      = -18; /* End of input */
static const int SXERR_PERM     = -19; /* Permission error */
static const int SXERR_NOOP     = -20; /* No-op */
static const int SXERR_FORMAT   = -21; /* Invalid format */
static const int SXERR_NEXT     = -22; /* Not an error */
static const int SXERR_OS       = -23; /* System call return an error */
static const int SXERR_CORRUPT  = -24; /* Corrupted pointer */
static const int SXERR_CONTINUE = -25; /* Not an error: Operation in progress */
static const int SXERR_NOMATCH  = -26; /* No match */
static const int SXERR_RESET    = -27; /* Operation reset */
static const int SXERR_DONE     = -28; /* Not an error */
static const int SXERR_SHORT    = -29; /* Buffer too short */
static const int SXERR_PATH     = -30; /* Path error */
static const int SXERR_TIMEOUT  = -31; /* Timeout */
static const int SXERR_BIG      = -32; /* Too big for processing */
static const int SXERR_RETRY    = -33; /* Retry your call */
static const int SXERR_IGNORE   = -63; /* Ignore */

static const int UNQLITE_NOMEM    = SXERR_MEM;     /* Out of memory */
static const int UNQLITE_ABORT    = SXERR_ABORT;   /* Another thread have released this instance */
static const int UNQLITE_IOERR    = SXERR_IO;      /* IO error */
static const int UNQLITE_CORRUPT  = SXERR_CORRUPT; /* Corrupt pointer */
static const int UNQLITE_LOCKED   = SXERR_LOCKED;  /* Forbidden Operation */
static const int UNQLITE_BUSY	    = SXERR_BUSY;    /* The database file is locked */
static const int UNQLITE_DONE	    = SXERR_DONE;    /* Operation done */
static const int UNQLITE_PERM     = SXERR_PERM;    /* Permission error */
static const int UNQLITE_NOTIMPLEMENTED = SXERR_NOTIMPLEMENTED; /* Method not implemented by the underlying Key/Value storage engine */
static const int UNQLITE_NOTFOUND = SXERR_NOTFOUND; /* No such record */
static const int UNQLITE_NOOP     = SXERR_NOOP;     /* No such method */
static const int UNQLITE_INVALID  = SXERR_INVALID;  /* Invalid parameter */
static const int UNQLITE_EOF      = SXERR_EOF;      /* End Of Input */
static const int UNQLITE_UNKNOWN  = SXERR_UNKNOWN;  /* Unknown configuration option */
static const int UNQLITE_LIMIT    = SXERR_LIMIT;    /* Database limit reached */
static const int UNQLITE_EXISTS   = SXERR_EXISTS;   /* Record exists */
static const int UNQLITE_EMPTY    = SXERR_EMPTY;    /* Empty record */

static const int UNQLITE_OPEN_READONLY         = 1;
static const int UNQLITE_OPEN_READWRITE        = 2;
static const int UNQLITE_OPEN_CREATE           = 4;
static const int UNQLITE_OPEN_EXCLUSIVE        = 8;
static const int UNQLITE_OPEN_TEMP_DB          = 16;
static const int UNQLITE_OPEN_NOMUTEX          = 32;
static const int UNQLITE_OPEN_OMIT_JOURNALING  = 64;
static const int UNQLITE_OPEN_IN_MEMORY        = 128;
static const int UNQLITE_OPEN_MMAP             = 256;

static const int UNQLITE_CONFIG_JX9_ERR_LOG         = 1;  /* TWO ARGUMENTS: const char **pzBuf, int *pLen */
static const int UNQLITE_CONFIG_MAX_PAGE_CACHE      = 2;  /* ONE ARGUMENT: int nMaxPage */
static const int UNQLITE_CONFIG_ERR_LOG             = 3;  /* TWO ARGUMENTS: const char **pzBuf, int *pLen */
static const int UNQLITE_CONFIG_KV_ENGINE           = 4;  /* ONE ARGUMENT: const char *zKvName */
static const int UNQLITE_CONFIG_DISABLE_AUTO_COMMIT = 5;  /* NO ARGUMENTS */
static const int UNQLITE_CONFIG_GET_KV_NAME         = 6;  /* ONE ARGUMENT: const char **pzPtr */

typedef signed long long int   sxi64; /* 64 bits(8 bytes) signed int64 */
typedef unsigned long long int sxu64; /* 64 bits(8 bytes) unsigned int64 */

typedef struct unqlite unqlite;
typedef sxi64 uqlite_real;
typedef double unqlite_real;
typedef sxi64 unqlite_int64;

typedef struct unqlite_kv_engine unqlite_kv_engine;
typedef struct unqlite_kv_cursor unqlite_kv_cursor;

int unqlite_open(unqlite **ppDB, const char *zFilename, unsigned int iMode);
int unqlite_close(unqlite *pDb);
int unqlite_kv_store(unqlite *pDb,const void *pKey,int nKeyLen,const void *pData,unqlite_int64 nDataLen);
int unqlite_kv_append(unqlite *pDb,const void *pKey,int nKeyLen,const void *pData,unqlite_int64 nDataLen);
int unqlite_kv_store_fmt(unqlite *pDb,const void *pKey,int nKeyLen,const char *zFormat,...);
int unqlite_kv_append_fmt(unqlite *pDb,const void *pKey,int nKeyLen,const char *zFormat,...);
int unqlite_kv_fetch(unqlite *pDb,const void *pKey,int nKeyLen,void *pBuf,unqlite_int64 /* in|out */*pBufLen);
int unqlite_kv_fetch_callback(unqlite *pDb,const void *pKey, int nKeyLen,int (*xConsumer)(const void *,unsigned int,void *),void *pUserData);
int unqlite_kv_delete(unqlite *pDb,const void *pKey,int nKeyLen);

int unqlite_kv_cursor_init(unqlite *pDb,unqlite_kv_cursor **ppOut);
int unqlite_kv_cursor_release(unqlite *pDb,unqlite_kv_cursor *pCur);
int unqlite_kv_cursor_seek(unqlite_kv_cursor *pCursor,const void *pKey,int nKeyLen,int iPos);
int unqlite_kv_cursor_first_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_last_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_valid_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_next_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_prev_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_key(unqlite_kv_cursor *pCursor,void *pBuf,int *pnByte);
int unqlite_kv_cursor_key_callback(unqlite_kv_cursor *pCursor,int (*xConsumer)(const void *,unsigned int,void *),void *pUserData);
int unqlite_kv_cursor_data(unqlite_kv_cursor *pCursor,void *pBuf,unqlite_int64 *pnData);
int unqlite_kv_cursor_data_callback(unqlite_kv_cursor *pCursor,int (*xConsumer)(const void *,unsigned int,void *),void *pUserData);
int unqlite_kv_cursor_delete_entry(unqlite_kv_cursor *pCursor);
int unqlite_kv_cursor_reset(unqlite_kv_cursor *pCursor);

int unqlite_begin(unqlite *pDb);
int unqlite_commit(unqlite *pDb);
int unqlite_rollback(unqlite *pDb);

int unqlite_config(unqlite *pDb,int nOp,...);

unsigned int unqlite_util_random_num(unqlite *pDb);

typedef struct {
	void * db;
} UnqliteDBHandle;

typedef struct {
	void * cur;
	void * db;
} UnqliteCursorHandle;

typedef int (__stdcall *xConsumer)(const void *,unsigned int,void *);

]]

local open_modes = {
	readonly = Lib.UNQLITE_OPEN_READONLY,
	readwrite = Lib.UNQLITE_OPEN_READWRITE,
	create = Lib.UNQLITE_OPEN_CREATE,
	memory = Lib.UNQLITE_OPEN_IN_MEMORY,
	mmap = Lib.UNQLITE_OPEN_MMAP,
}

local error_codes = {}
error_codes[Lib.UNQLITE_NOMEM] = "Out of memory"
error_codes[Lib.UNQLITE_ABORT] = "Another thread have released this instance"
error_codes[Lib.UNQLITE_IOERR] = "IO error"
error_codes[Lib.UNQLITE_CORRUPT] = "Corrupt pointer"
error_codes[Lib.UNQLITE_LOCKED] = "Forbidden Operation"
error_codes[Lib.UNQLITE_BUSY] = "The database file is locked"
error_codes[Lib.UNQLITE_DONE] = "Operation done"
error_codes[Lib.UNQLITE_PERM] = "Permission error"
error_codes[Lib.UNQLITE_NOTIMPLEMENTED] = "Method not implemented by the underlying Key/Value storage engine"
error_codes[Lib.UNQLITE_NOTFOUND] = "No such record"
error_codes[Lib.UNQLITE_NOOP] = "No such method"
error_codes[Lib.UNQLITE_INVALID] = "Invalid parameter"
error_codes[Lib.UNQLITE_EOF] = "End Of Input"
error_codes[Lib.UNQLITE_UNKNOWN] = "Unknown configuration option"
error_codes[Lib.UNQLITE_LIMIT] = "Database limit reached"
error_codes[Lib.UNQLITE_EXISTS] = "Record exists"
error_codes[Lib.UNQLITE_EMPTY] = "Empty record"

local function handleError(rc)
	if rc == Lib.UNQLITE_OK then
		return true
	end
	local rv = error_codes[rc]
	if rv then
		return nil, rv
	end
	return nil, rc
end

local UnqliteDBHandle = ffi.typeof("UnqliteDBHandle")
local UnqliteDBHandle_mt = {
	__new = function(ct, rawHandle)
		return ffi.new(ct, rawHandle)
	end,
	__gc = function(self)
		if self.db == nil then
			return
		end
		Lib.unqlite_close(self.db)
		self.db = nil
	end,
}
ffi.metatype(UnqliteDBHandle, UnqliteDBHandle_mt)

local UnqliteCursorHandle = ffi.typeof("UnqliteCursorHandle")
local UnqliteCursorHandle_mt = {
	__new = function(ct, rawCursorHandle, rawHandle)
		return ffi.new(ct, rawCursorHandle, rawHandle)
	end,
	__gc = function(self)
		if self.cur == nil then
			return
		end
		if self.db ~= nil then
			Lib.unqlite_kv_cursor_release(self.db, self.cur)
		end
		self.cur = nil
	end,
}
ffi.metatype(UnqliteCursorHandle, UnqliteCursorHandle_mt)

local unqlite = {}

local new_db_ptr = ffi.typeof("unqlite*[1]")
local new_cursor_ptr = ffi.typeof("unqlite_kv_cursor *[1]")

local unqlitedb = {}
unqlitedb.__index = unqlitedb
function unqlitedb:__call(...)
	return self:exec(...)
end

local unqlitecursor = {}
unqlitecursor.__index = unqlitecursor
function unqlitecursor:__call(...)
	return self:exec(...)
end

function unqlite.open(filename, mode)
	local db = ffi.new("unqlite*[1]")
	local open_mode = open_modes[mode or "create"]
	local rc = Lib.unqlite_open(db, filename, open_mode)
	if rc ~= Lib.UNQLITE_OK then
		return nil
	end
	local handle = UnqliteDBHandle(db[0])
	local ret = {
		db = handle.db,
		handle = handle,
	}
	return setmetatable(ret, unqlitedb)
end

function unqlitedb:close()
	local rc = Lib.unqlite_close(self.db)
	if rc == Lib.UNQLITE_OK then
		self.handle.db = nil
		self.handle = nil
		self.db = nil
	end
	return handleError(rc)
end

function unqlitedb:set(key, value)
	local rc = Lib.unqlite_kv_store(self.db, key, #key, value, #value)
	return handleError(rc)
end

local ConsumerCallbackVal
local ConsumerCallback = ffi.cast("xConsumer", function(c, i, d)
	ConsumerCallbackVal = ffi.string(c, i)
	return (0)
end)

function unqlitedb:get(key)
	local rc = Lib.unqlite_kv_fetch_callback(self.db, key, #key, ConsumerCallback, nil)
	if rc == Lib.UNQLITE_OK then
		return ConsumerCallbackVal
	elseif rc == Lib.UNQLITE_NOTFOUND then
		return nil
	end
	return handleError(rc)
end

function unqlitedb:append(key, value)
	local rc = Lib.unqlite_kv_append(self.db, key, #key, value, #value)
	return handleError(rc)
end

function unqlitedb:delete(key)
	local rc = Lib.unqlite_kv_delete(self.db, key, #key)
	if rc == Lib.UNQLITE_NOTFOUND then
		return true -- deletes succeed on key not found
	end
	return handleError(rc)
end

function unqlitedb:begin()
	local rc = Lib.unqlite_begin(self.db)
	return handleError(rc)
end

function unqlitedb:commit()
	local rc = Lib.unqlite_commit(self.db)
	return handleError(rc)
end

function unqlitedb:rollback()
	local rc = Lib.unqlite_rollback(self.db)
	return handleError(rc)
end

function unqlitedb:cursor()
	local cur = new_cursor_ptr()
	local rc = Lib.unqlite_kv_cursor_init(self.db, cur)
	if rc ~= Lib.UNQLITE_OK then
		return handleError(rc)
	end
	local handle = UnqliteCursorHandle(cur[0], self.db)
	local ret = {
		db = self.db,
		cur = handle.cur,
		handle = handle,
	}
	return setmetatable(ret, unqlitecursor)
end

function unqlitecursor:first()
	local rc = Lib.unqlite_kv_cursor_first_entry(self.cur)
	return handleError(rc)
end

function unqlitecursor:next_entry()
	local rc = Lib.unqlite_kv_cursor_next_entry(self.cur)
	if rc == Lib.UNQLITE_DONE then
		return nil
	end
	return handleError(rc)
end

function unqlitecursor:delete_entry()
	local rc = Lib.unqlite_kv_cursor_delete_entry(self.cur)
	return handleError(rc)
end


function unqlitecursor:key()
	local val
	local cb = ffi.cast("xConsumer", function(c, i, d)
		val = ffi.string(c, i)
		return 0
	end)
	local rc = Lib.unqlite_kv_cursor_key_callback(self.cur, cb, nil)
	cb:free()
	if rc == Lib.UNQLITE_OK then
		return val
	end
	return handleError(rc)
end

function unqlitecursor:data()
	local val
	local cb = ffi.cast("xConsumer", function(c, i, d)
		val = ffi.string(c, i)
		return 0
	end)
	local rc = Lib.unqlite_kv_cursor_data_callback(self.cur, cb, nil)
	cb:free()
	if rc == Lib.UNQLITE_OK then
		return val
	end
	return handleError(rc)
end

function unqlitecursor:release()
	local rc = Lib.unqlite_kv_cursor_release(self.db, self.cur)
	self.handle.cur = nil
	self.handle = nil
	return handleError(rc)
end

return unqlite
