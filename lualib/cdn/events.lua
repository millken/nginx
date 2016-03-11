local cjson = require "cjson"
local config = require "cdn.config"
local log = require "cdn.log"

local redis_mod = require "resty.redis"
local dyups = require "ngx.dyups"
local sqlite3 = require "sqlite3"
local cmsgpack = require "cmsgpack"

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
		redis = { host = "127.0.0.1", port = 6379 },
        upstream_connect_timeout = 500,
    }
    return setmetatable({ config = config, redis = nil }, mt)
end


_M.events = {
	flush_config = {"lock", "set_empty_config", "unlock"},
	load_config = {"lock", "load_config", "unlock"},
	reload_config = {"lock", "set_empty_config", "load_config", "unlock"},
	add_config = {"lock", "delete_config", "set_config", "unlock"},
	remove_config = {"delete_config"}
}

_M.states = {
	lock = function(self)
		locked:set("states", 1)
	end,

	unlock = function(self)
		locked:set("states", 0)
	end,

	load_config = function(self)
		local db = sqlite3.open(config:get('db.file'),  "ro")
		local last_date = db:rowexec("select max(created_at) from event")
		settings:set("event_date", last_date)
		local server, n = db:exec("SELECT * FROM server", "hk")
		local t1 = ngx_now()
		local i
		for i=1, n do
			log:debug("servername: ",  server.servername[i] , ", setting :", server.setting[i])
			settings:set(server.servername[i] , server.setting[i])
		end
		local t2 = ngx_now() - t1 
		db:close()
		log:info("load config cost time : ", t2, "ms")
	end,

	set_config = function(self, servername)
		local db = sqlite3.open(config:get('db.file'),  "ro")
		local setting = db:rowexec("select setting from server where servername='" .. servername .. "'")
		db:close()
		settings:set(servername, setting)
	end,

	delete_config = function(self, servername)
		local setting_json = settings:get(servername)
		if setting_json == nil then
			return false
		end
		local setting = cjson.decode(setting_json)
		local k
		for k, _ in pairs(setting) do
			dyups.delete(k)
			upstream_cached:delete(k)
		end
		settings:delete(hostname)
		return true
	end,

	set_empty_config = function(self)
		settings:flush_all()
		wsettings:flush_all()
		upstreams:flush_all()
		upstream_cached:flush_all()
	end,
}

function _M.states_locked()
	if locked:get("states") == 1 then
		return true
	else
		return false
	end
end

function _M.e(self, event, servername)
	local servername = servername
	if servername == nil then
		servername = "default"
	end
    log:info("#e: ", servername, "|", event)
	local events = self.events[event]
	if not events then
        ngx_log(ngx_ERR, event, " is not defined.")
	else
		if type(events) == "table" then
			for _, state in ipairs(events) do
				log:debug("#t: ", servername, "|", state)
				self.states[state](self, servername)
			end
		else
			log:debug("#t: ", servername, "|", events)
			self.states[events](self, servername)
		end
    end
end

return _M
