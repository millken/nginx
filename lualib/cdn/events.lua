local cjson = require "cjson"
local config = require "cdn.config"
local log = require "cdn.log"
local hosts = require "cdn.hosts"

local redis_mod = require "resty.redis"
local dyups = require "ngx.dyups"
local db = require "cdn.postgres"
local cmsgpack = require "cmsgpack"
local lock = require "resty.lock"
local time = require "cdn.time"

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
        
local ngx_log = ngx.log
local ngx_var = ngx.var
local ngx_re_find = ngx.re.find
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local str_sub = string.sub

local settings = ngx.shared.settings
local locked = ngx.shared.locked
local upstream_cached = ngx.shared.upstream_cached

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

function _M.new(self)
 	local config = {
    }
    return setmetatable({ config = config, redis = nil }, mt)
end


_M.events = {
	flush_config = {"set_empty_setting"},
	load_config = {"load_config"},
	reload_config = {"set_empty_setting", "load_config", "set_empty_upstream_cached"},
	add_config = {"delete_config", "set_config"},
	remove_config = {"delete_config"}
}

_M.states = {
	load_config = function(self)
		local t1 = time.gettimeofday()
		local ok, res = db:query("select max(utime) from config.event")
		if not ok then
			log:error("query event events err: ", res)
			return
		end
		if #res > 0 then
			settings:set("event_last_utime", res[1].max)
			log:info("last update time for event: ", res[1].max)
		end
		local ok, res = db:query_row("select max(id),count(id) from config.server")
		if not ok then
			log:error("[events.load_config] query max(id), count(id) error")
			return 
		end
		log:debug("[events.load_config] max(id) = ", res.max ,", count(id) = ", res.count)
		local offset = 0
		local max_id = res.max
		local limit = 2500
		while offset <= res.count do
			local ok, res = db:query("SELECT * FROM config.server where id<= " .. max_id .. " order by id asc limit " .. limit .. " offset " .. offset)
			if not ok or #res == 0 then
				log:alert("[events.load_config] failed to query server", res)
				break
			end
			for i=1, #res do
				local s = res[i]
				if s.servername == ngx.null then
					log:error("id=", s.id, " servername error")
				else
					log:debug("load host: ", s.servername, s.setting)
					local setting = cmsgpack.pack(cjson_decode(s.setting))
					local success, err, forcible = settings:set(s.servername , setting)
					if not success then 
						log:error("events settings:set ", s.servername, err)
					end
				end
			end
			offset = offset + #res
			res = nil
		end
		db:close()
		local t2 = time.gettimeofday() - t1 
		log:info("load config cost time : ", t2/1000, "ms")
	end,

	set_config = function(self, servername, setting)
		if setting ~= ngx.null then
			local setting = cmsgpack.pack(cjson_decode(setting))
			local success, err, forcible = settings:set(servername , setting)
			if not success then
				log:error("set_config error : ", err)
			end
			return
		end
		local ok, res = db:query("select setting from config.server  where servername='" .. servername .."'")
		if not ok then
			log:error("set_config query err: ", res)
			return
		end
		if #res >0 then
			local r = res[1]
			local setting = cmsgpack.pack(cjson_decode(r.setting))
			local success, err, forcible = settings:set(servername , setting)
			if not success then
				log:error("set_config error : ", err)
			end
		
		else
			log:error("failed to found setting: ", servername)
		end
	end,

	delete_config = function(self, servername)
		log:debug("delete host: ", servername)
		hosts.delete_cache(servername)
		local setting_json = settings:get(servername)
		if setting_json == nil then
			return false
		end
		local setting = cmsgpack.unpack(setting_json)
		local k
		for k, _ in pairs(setting) do
			log:debug("delete vhost: ", k)
			dyups.delete(k)
			upstream_cached:delete(k)
		end
		settings:delete(servername)
		return true
	end,

	set_empty_setting = function(self)
		settings:flush_all()
	end,

	set_empty_upstream_cached = function(self)
		upstream_cached:flush_all()
	end,
}

function _M.e(self, event, servername, setting)
	local servername = servername
	local event = event
	if servername == nil then
		servername = "default"
	end
	if event == nil then
		return
	end
    log:info("#e: ", servername, "[", event, "]")
	local events = self.events[event]
	if not events then
        log:error("servername: ", servername, ", event: ", event, " is not defined.")
	else
		if type(events) == "table" then
			for _, state in ipairs(events) do
				--log:debug("#t: ", servername, "|", state)
				self.states[state](self, servername, setting)
			end
		else
			--log:debug("#t: ", servername, "|", events)
			self.states[events](self, servername, setting)
		end
    end
end

return _M
