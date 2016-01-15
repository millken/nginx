local cjson = require "cjson"
local redis_mod = require "resty.redis"
local dyups = require "ngx.dyups"

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
        
local ngx_log = ngx.log
local ngx_var = ngx.var
local ngx_re_find = ngx.re.find
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local tbl_insert = table.insert
local co_create = coroutine.create
local co_status = coroutine.status
local co_resume = coroutine.resume
local co_yield = coroutine.yield

local upstreams = ngx.shared.upstreams
local settings = ngx.shared.settings
local wsettings = ngx.shared.wsettings

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local DEFAULT_OPTIONS = {
	concurrency = 1,
    interval = 10,
}


function _M.new(self)
 	local config = {
        origin_mode     = _M.ORIGIN_MODE_NORMAL,

        upstream_connect_timeout = 500,
    }
    return setmetatable({ config = config }, mt)
end

function _M.rewrite(self)
	if (settings:get(ngx_var.host) == nil) then

		for _, k in pairs(wsettings:get_keys()) do
		    local from, to, err = ngx_re_find(ngx_var.host, k)
		    ngx_log(ngx_INFO, "k : " .. k)
		    if from then
		        ngx_var.hostgroup = wsettings:get(k)
		    else
		        if err then
		            ngx_log(ngx_ERR, "Match ERR! "..err)
		        end
		        ngx.exit(404)
		    end
		end

	else
		ngx_var.hostgroup = ngx_var.host
	end
	dyups.update(ngx_var.hostgroup, upstreams:get(ngx_var.hostgroup))
end

function _M.set_config(hostname, sett)
	ngx_log(ngx_INFO,"hostname :" .. hostname .. ", setting :" .. sett)
    local tmpkv = {}
    local gsett = cjson.decode(sett)
    if gsett ~= nil then
        for k,v in pairs(gsett) do
            if (k=="upstream") then
				upstreams:set(hostname, v)
				ngx_log(ngx_INFO,"hostname :" .. hostname .. ", ups :" .. v)
            elseif k=="server_type" then
                if v==1 then
                    ngx_log(ngx_INFO,"got a wildcard domain set")
                    wsettings:set(gsett["wildname"], hostname)
                end
            else
                tmpkv[k]=v
            end
        end
    	settings:set(hostname, cjson.encode(tmpkv))
    else
    	ngx_log(ngx_ERR, "get sett empty")
    end	
end

function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker(premature)
    	local redis
        if not premature then
        	local redis = redis_mod:new()
            local ok, err = redis:connect("127.0.0.1",6379)
            if not ok then
                ngx_log(ngx_ERR, "could not connect to Redis: ", err)

                local ok, err = ngx_timer_at(options.interval, worker)
                if not ok then
                    ngx_log(ngx_ERR, "failed to run worker: ", err)
                else
                    return ok
                end
            end

            ngx_log(ngx_INFO, "connected to redis done")
            local sites = redis:keys("site_*")
            if sites then
                for _,host in ipairs(sites) do
                    local hostname = string.sub(host, 6)
                    local sett = redis:get(host)
                    self.set_config(hostname, sett)
                end
            end
            
            local ok, err = ngx_timer_at(options.interval, worker)
            if not ok then
                ngx_log(ngx_ERR, "failed to run worker: ", err)
            end
        end
    end
    for i = 1,(options.concurrency) do
        local ok, err = ngx_timer_at(i, worker)
        if not ok then
            ngx_log(ngx_ERR, "failed to start worker: ", err)
        end
    end
end

return _M
