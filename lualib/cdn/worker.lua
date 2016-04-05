local cjson = require "cjson"
local db = require "cdn.postgres"
local cmsgpack = require "cmsgpack"

local dyups = require "ngx.dyups"
local events = require "cdn.events"
local config = require "cdn.config"
local hosts = require "cdn.hosts"
local log = require "cdn.log"
local lock = require "resty.lock"
local open = io.open
local ngx = ngx
local ngx_var = ngx.var
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

function _M.rewrite()
	if ngx_var.ups == "" then return end
	local ups_key = hosts.get_ups_key(ngx_var.host)
	local ups_value 

	if ups_key == nil then
		ups_key, ups_value = hosts.get_ups(ngx_var.host)
	end

	if ups_key == nil then
		ngx.exit(404)
	end

	local ups_cache, _ = upstream_cached:get(ups_key)
	if not ups_cache then
		if ups_value == nil then
			ups_key, ups_value = hosts.get_ups(ngx_var.host)
		end
		if ups_key == nil or ups_value == nil then
			ngx.exit(404)
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
	local setting, err = hosts.get_setting(ngx_var.host)
	if setting then
		config:set("upsconf", setting[ups_key])
	end
	ngx_var.ups = ups_key
end

function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })
	local locked = lock:new("locked", {exptime = 300, step = 0.5})

    local function worker(premature)
		if premature then  return  end
		local elapsed, err = locked:lock("worker")
		if elapsed then
			local ok, err = settings:safe_add("localhost", true)
			if ok then
				log:info("loading config from db")
				events:e("load_config")
			end
			while not ngx.worker.exiting() do
				local utime = settings:get("event_last_utime")
				if not utime then
					break
				end
				--utime = '2016-03-11 11:35:19.688017'
				local ok, res = db:query("select event.servername, utime, act, setting setting from config.event left outer join config.server on event.servername = server.servername where utime>'" .. utime .."' order by utime asc")
				--local ok, res = db:query("select servername, utime, act from config.event  where utime>'" .. utime .."' order by utime asc")
				if not ok then
					log:error("query event worker err: ", res)
					break
				end
				for i=1, #res do
					local r = res[i]
					events:e(r.act, r.servername, r.setting)
					settings:set("event_last_utime", r.utime)
				end
				ngx.sleep(3)
			end
			local ok, err = locked:unlock()
			if not ok then
				log:error("failed to unlock worker: ", err)
			end
		end
		local ok, err = ngx_timer_at(options.interval, worker)
		if not ok then
			upstream_cached:flush_all()
			db:close()		
			log:error("failed to run worker: ", err)
		end
	end
	local ok, err = ngx_timer_at(0, worker)
	if not ok then
		log:error("failed to start worker: ", err)
	end
end

return _M
