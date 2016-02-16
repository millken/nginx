local ngx = ngx
local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack

local _M = {
    _VERSION = '0.01',
	config = {},
}

local mt = { __index = _M }

function _M.ctx(self)
    local id = tostring(self)
    local ctx = ngx.ctx[id]
    if not ctx then
        ctx = {
            config = {},
        }
        ngx.ctx[id] = ctx
    end
    return ctx
end


function _M.set(self, param, value)
    if ngx.get_phase() == "init" then
        self.config[param] = value
    else
        self:ctx().config[param] = value
    end
end

function _M.get(self, param)
    local p = self:ctx().config[param]
    if p == nil then
        return self.config[param]
    else
        return p
    end
end

return _M
