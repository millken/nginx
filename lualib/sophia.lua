local sophia = require("sophia.sophia")

local _M = { _VERSION = '0.1',
        }

local mt = { __index = _M }

function _M.new(self, path)
    local db = nil
    local err = nil

    if not db then
        db, err = sophia.SophiaDatabase(path);
        if err then
            return nil, err
        end
    end

    self.db = db

    return setmetatable({ db = db }, mt)
end

function _M.close(self)
    local db = self.db
    db:close()
    self.db = nil
end

function _M.put(self, key, value)
    local db = self.db

    local ok, err = db:upsert(key, value)
    return ok, err
end

function _M.get(self, key)
    local db = self.db
    local value, err = db:retrieve(key, #key)
    return value, err
end

function _M.del(self, key)
    local db = self.db
    local ok = db:delete(key, #key)

    return ok
end


return _M