local sophia = require("sophia.sophia")()
local ffi = require("ffi")
local libc = require("sophia.libc")()
local ngx_log = ngx.log

local _M = { _VERSION = '0.1',
        }

local mt = { __index = _M }

function _M.new(self, path)
    local env = sp_env();
    sp_setstring(env, "sophia.path", "_test", 0);
    sp_setstring(env, "db", "test", 0);
    local db = sp_getobject(env, "db.test");
    local rc = sp_open(env);
    if (rc == -1) then
        return nil, error(rc);
    end
    --self.db = db

    return setmetatable({ db = db }, mt)
end

function _M.close(self)
    local db = self.db
    db:close()
    self.db = nil
end

function _M.put(self, key, value)
    local db = self.db

    local key = ffi.new("uint32_t[1]", 1);
    local o = sp_object(db);
    sp_setstring(o, "key", key, ffi.sizeof("uint32_t"));
    sp_setstring(o, "value", key, ffi.sizeof("uint32_t"));
    rc = sp_set(db, o);
    if (rc == -1) then
        return false, error(rc);
    end
    return true, nil
end

function _M.get(self, key)
    local db = self.db

end

function _M.del(self, key)
    local db = self.db
    return true
end


return _M