local cjson = require "cjson"
local config = require "cdn.config"
local log = require "cdn.log"

local redis_mod = require "resty.redis"
local dyups = require "ngx.dyups"
local sqlite3 = require "sqlite3"
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

local upstreams = ngx.shared.upstreams
local settings = ngx.shared.settings
local wsettings = ngx.shared.wsettings
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

function _M.set_config(hostname, sett)
	ngx_log(ngx_DEBUG,"hostname :" .. hostname .. ", setting :" .. sett)
    local tmpkv = {}
    local gsett = cjson_decode(sett)
    if gsett ~= nil then
        for k,v in pairs(gsett) do
            if (k=="upstream") then
				--dyups.update(hostname, v)
				upstreams:set(hostname, v)
				--ngx_log(ngx_INFO,"hostname :" .. hostname .. ", ups :" .. v)
            elseif k=="server_type" then
                if v==1 then
                    --ngx_log(ngx_INFO,"got a wildcard domain set")
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

_M.events = {
	flush_config = {"lock", "set_empty_config", "unlock"},
	load_config = {"lock", "load_config", "unlock"},
	reload_config = {"lock", "set_empty_config", "connect_redis", "load_config", "unlock"},
	add_config = {"lock", "set_config", "unlock"},
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
		local server, n = db:exec("SELECT * FROM server", "hk")
		local t1 = ngx_now()
		local i
		for i=1, n do
			log:debug( server.servername[i] .. server.setting[i])
		end
		local t2 = ngx_now() - t1 
		ngx_log(ngx.NOTICE , "load config cost time : ", t2)
	end,

	set_config = function(self, body)
		local bjson = cjson_decode(body)
		self.set_config(bjson["hostname"], cjson_encode(bjson["sett"]))
	end,

	delete_config = function(self, body)
		local bjson = cjson_decode(body)
		local hostname = bjson["hostname"] or ""
		dyups.delete(hostname)
		settings:delete(hostname)
		upstreams:delete(hostname)
		upstream_cached:delete(hostname)
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

function _M.e(self, event)
    log:info("#e: " .. event)
	local events = self.events[event]
	if not events then
        ngx_log(ngx_ERR, event, " is not defined.")
	else
		if type(events) == "table" then
			for _, state in ipairs(events) do
				log:debug("#t: " .. state)
				self.states[state](self)
			end
		else
			log:debug("#t: " .. events)
			self.states[events](self)
		end
    end
end

return _M
