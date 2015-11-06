local   setmetatable, tostring, ipairs, pairs, type, tonumber, next, unpack =
        setmetatable, tostring, ipairs, pairs, type, tonumber, next, unpack

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_NOTICE = ngx.NOTICE
local ngx_INFO = ngx.INFO
local ngx_null = ngx.null
local ngx_print = ngx.print
--using
local str_lower = string.lower
local ngx_get_phase = ngx.get_phase
local ngx_req_get_headers = ngx.req.get_headers

local _M = {
    _VERSION = '0.1'
}

local mt = {
    __index = _M,
}

function _M.new()
    return setmetatable({}, mt)
end

function _M.get_ups(self)
	local host = str_lower(ngx_req_get_headers()["Host"] or "")
    for k,v in pairs(ngx.ctx._host) do
    	if k == host then 
    		return ngx.ctx._ups[v]
    	end
    end
    return nil
end

function _M.load(self, config)
	local host = {}
    for k,v in pairs(config) do
    	if k == "vhost" then
    		for _,v in ipairs(v) do
    			host[v.server] = v.ups
    		end
    	elseif k == "ups" then
    		ngx.ctx._ups = v
    	elseif k == "cache" then
    	elseif k == "master" then
    		ngx.ctx._master = v
    	end
    end
    ngx.ctx._host = host
end


return _M        
