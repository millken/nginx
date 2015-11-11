local json_safe = require "cjson"
local unqlite = require 'unqlite'
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG

local _M = {
    _VERSION = '0.1', 
}

local mt = {
    __index = _M,
}
function _M.new(self)
    return setmetatable({ db = nil }, mt)
end

function _M.open(self, file)
    local db = unqlite.open(file)
    if not db then
        return nil, err
    end
    self.db = db
    return db ,nil
end

function _M.set(self, key, value)
    self.db:set( key, value)
end

function _M.get(self, key)
    self.db:get(key)
end

return _M
