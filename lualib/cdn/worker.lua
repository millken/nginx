local cjson = require "cjson"
local redis_mod = require "resty.redis"
local db = require "cdn.postgres"

local dyups = require "ngx.dyups"
local events = require "cdn.events"
local config = require "cdn.config"
local log = require "cdn.log"
local tlds = require "cdn.tlds"
local lrucache_mod = require "resty.lrucache"
local lock = require "resty.lock"
local lrucache, err = lrucache_mod.new(500)
if not lrucache then 
	error("failed to create the cache: " .. (err or "unknown"))	
end

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
local open = io.open
local ngx = ngx
local ngx_log = ngx.log
local ngx_var = ngx.var
local ngx_re_find = ngx.re.find
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at

local settings = ngx.shared.settings
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

local function get_ups_by_host(host)
	local ups_key, ups_value = nil, nil
	local topleveldomain = tlds:domain(ngx_var.host)
	if topleveldomain == nil then
		log:error("failed to fetch topleveldomain: ", host)
		return nil, nil
	end
	local setting_json = settings:get(topleveldomain)
	if setting_json == nil then
		log:error("failed to fetch setting: ", topleveldomain)
		return nil, nil
	end
	log:debug("topleveldomain :", topleveldomain, ", setting :", setting_json)
	local setting = cjson.decode(setting_json)
	if setting[ngx_var.host] == nil then
		for k, v in pairs(setting) do
			local i = k:find("%*")
			if i then 
				local from, to, err = ngx_re_find(ngx_var.host, k)
			log:debug(k, "*", i, from, v.ups)
				if from and v.ups ~= nil then
					ups_key = k
					lrucache:set(ngx_var.host, ups_key)
					ups_value = v.ups
					break
				end
			end
		end
	else
		local v = setting[ngx_var.host]
		if v.ups ~= nil then
			ups_key = ngx_var.host
			lrucache:set(ngx_var.host, ups_key)
			ups_value = v.ups
		end
	end
	return ups_key, ups_value
end

function _M.rewrite(self)
	local ups_key = lrucache:get(ngx_var.host)
	local ups_value 

	if ups_key == nil then
		ups_key, ups_value = get_ups_by_host(ngx_var.host)
	end

	if ups_key == nil then
		ngx.exit(404)
	end

	local ups_cache, _ = upstream_cached:get(ups_key)
	if not ups_cache then
		if ups_value == nil then
			ups_key, ups_value = get_ups_by_host(ngx_var.host)
		end
		local ok, err = upstream_cached:safe_add(ups_key, ups_value)
		if ok then
			local status, rv = dyups.update(ups_key, ups_value)
			if status ~= ngx.HTTP_OK then
				log:error("dyups update err: [", status, "]", rv)
			else
				log:info("load servername : ", ups_key, ", upstream: ", ups_value)
			end
		else
			log:error("upstream cached safe add error: ", err)
		end
	end
	ngx_var.ups = ups_key
end

function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker()
		local locked = lock:new("locked")
		local elapsed, err = locked:lock("worker")
		if elapsed then
			local ok, err = settings:safe_add("localhost", "")
			if ok then
			    log:info("loading config from db")
				events:e("load_config")
			end
			while true do
				local utime = settings:get("event_last_utime")
				utime = '2016-03-11 11:35:19.688017'
				local ok, res = db:query("select event.servername, utime, act, setting setting from config.event left outer join config.server on event.servername = server.servername where utime>'" .. utime .."' order by utime asc")
				--local ok, res = db:query("select servername, utime, act from config.event  where utime>'" .. utime .."' order by utime asc")
				if not ok then
					log:error("query event err: ", res)
					break
				end
				for i=1, #res do
					local r = res[i]
					events:e(r.act, r.servername, r.setting)
					settings:set("event_last_utime", r.utime)
				end
				ngx.sleep(10)
			end
			local ok, err = locked:unlock()
			if not ok then
				log:error("failed to unlock worker: ", err)
			end
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
