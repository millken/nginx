local cjson = require "cjson"
local redis_mod = require "resty.redis"
local dyups = require "ngx.dyups"
local events_mod = require "cdn.events"

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
local locked = ngx.shared.locked

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
	if ngx_var.hostgroup == "" then
		ngx.exit(404)
	end
	--dyups.update(ngx_var.hostgroup, upstreams:get(ngx_var.hostgroup))
end

function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker()
		if locked:get("l") ~= 1 then
			locked:set("l", 1)
		local redis = redis_mod:new()
		local events = events_mod:new()
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
		local ok, err = settings:safe_add("localhost", "")
		if ok then
			ngx_log(ngx_INFO, "loading config from redis")
			events:e "reload_config"
		end
		redis:subscribe("cdn.event")
		while true do
			local msg, err = redis:read_reply()
			if not msg then
				ngx_log(ngx_ERR,"ERR:"..err)
				break
			end
			ngx_log(ngx_DEBUG, "redis reply: " .. cjson.encode(msg))
			local subs = cjson.decode(msg[3])
			
			events:e( subs["event"], msg[3] )
		end
		--locked:set("l", 0)

		end
		
		local ok, err = ngx_timer_at(options.interval, worker)
		if not ok then
			ngx_log(ngx_ERR, "failed to run worker: ", err)
		end
	end
	local ok, err = ngx_timer_at(0, worker)
	if not ok then
		ngx_log(ngx_ERR, "failed to start worker: ", err)
	end
end

return _M
