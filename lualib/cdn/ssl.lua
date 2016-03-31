local ssl = require "ngx.ssl"

local ngx = ngx
local ngx_var = ngx.var

local settings = ngx.shared.settings

local _M = {
    _VERSION = '0.01',
}


return _M
