local cjson = require "cjson"
local redis_mod = require "resty.redis"
local sqlite3 = require "sqlite3"

local dyups = require "ngx.dyups"
local events = require "cdn.events"
local config = require "cdn.config"
local log = require "cdn.log"
local tlds = require "cdn.tlds"
local lrucache_mod = require "resty.lrucache"
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
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode

local upstreams = ngx.shared.upstreams
local settings = ngx.shared.settings
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

local function get_ups_by_host(host)
	local ups_key, ups_value = nil, nil
	local topleveldomain = tlds:domain(ngx_var.host)
	if topleveldomain == nil then
		return nil, nil
	end
	local setting_json = settings:get(topleveldomain)
	if setting_json == nil then
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
				log:info("load upstream : ", ups_key, ups_value)
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
			while true do
				local db = sqlite3.open(config:get('db.file'),  "ro")
				local date = settings:get("event_date")
				local event, n = db:exec("SELECT * FROM event where created_at>'" .. date .."' order by created_at asc", "hk")
				db:close()
				for i=1, n do
					log:debug("servername: ",  event.servername[i] , ", event :", event.event[i], ", created_at: ", event.created_at[i])
					events:e(event.event[i], event.servername[i])
					settings:set("event_date", event.created_at[i])
				end
				ngx.sleep(1)
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
