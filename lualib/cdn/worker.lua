local db = require "cdn.postgres"

local events = require "cdn.events"
local log = require "cdn.log"
local lock = require "resty.lock"
local ngx = ngx
local ngx_var = ngx.var
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at

local settings = ngx.shared.settings
local upstream_cached = ngx.shared.upstream_cached

local _M = {
    _VERSION = 0.02,
}

local mt = { __index = _M }

local DEFAULT_OPTIONS = {
	concurrency = 1,
    interval = 10,
}

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
