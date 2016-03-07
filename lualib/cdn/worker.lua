local cjson = require "cjson"
local redis_mod = require "resty.redis"

local dyups = require "ngx.dyups"
local events = require "cdn.events"
local config = require "cdn.config"
local log = require "cdn.log"
local tlds = require "cdn.tlds"

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
local open = io.open   
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

local upstreams = ngx.shared.upstreams
local settings = ngx.shared.settings
local wsettings = ngx.shared.wsettings
local locked = ngx.shared.locked
local upstream_cached = ngx.shared.upstream_cached

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local DEFAULT_OPTIONS = {
	concurrency = 1,
    interval = 10,
}

local function file_exists(path)
	local file = open(path, "rb")
    if not file then return nil end
    --local content = file:read "*a"
    file:close()
	return true
end

function _M.rewrite(self)
	local topleveldomain = tlds:domain(ngx_var.host)
	if topleveldomain == nil then 
		ngx.exit(404)
	end
	local setting = settings:get(topleveldomain)
	if setting == nil then
		log:info("server config not found: ", topleveldomain)
		ngx.exit(404)
	end
	if (settings:get(ngx_var.host) == nil) then

		for _, k in pairs(wsettings:get_keys()) do
		    local from, to, err = ngx_re_find(ngx_var.host, k)
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
	local ups_cache, _ = upstream_cached:get(ngx_var.hostgroup)
	if not ups_cache then
		local ups, _ = upstreams:get(ngx_var.hostgroup) 
		if not ups then 
			ngx_log(ngx_ERR, "upstream not exist :", ngx_var.hostgroup)
			ngx.exit(421)
		else
			local ok, err = upstream_cached:safe_add(ngx_var.hostgroup, ups)
			if ok then
				dyups.update(ngx_var.hostgroup, ups)
				ngx_log(ngx_INFO, "load upstream : ", ngx_var.hostgroup, ups)
			end
		end
	end
end

function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker()
			if locked:get("worker") ~= 1 then
			locked:set("worker", 1)
			local sqlitefile = config:get('db.file')
			if not file_exists(sqlitefile) then
				log:error("can not open db file : ", sqlitefile)

				locked:set("worker", 0)
				local ok, err = ngx_timer_at(options.interval, worker)
				if not ok then
					log:error("failed to run worker: ", err)
				else
					return ok
				end			
			end

			local ok, err = settings:safe_add("localhost", "")
			if ok then
			    log:info("loading config from db")
				events:e("load_config")
			end
			locked:set("worker", 0)
			--log:debug("worker running")
		end
		
		local ok, err = ngx_timer_at(options.interval, worker)
		if not ok then
			log:error("failed to run worker: ", err)
		end
	end
	local ok, err = ngx_timer_at(0, worker)
	if not ok then
		log:error("failed to start worker: ", err)
	end
end

return _M
