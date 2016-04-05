local cjson = require "cjson"
local config = require "cdn.config"
local log = require "cdn.log"
local http_cache = require "http_cache"

local ipairs = ipairs
local str_find = string.find

local ngx = ngx
local ngx_var = ngx.var

local _M = {
    _VERSION = 0.01,
	events = {"cache"},
}

function _M.get_file_ext(uri)
    return uri:match(".+%.(%w+)$") or "none"
end

_M.states = {
	cache = function()
		local cache_status = (ngx_var.upstream_cache_status or "")
		local upsconf = config:get("upsconf")
		local cache_time = 0
		log:info("upsconf header: ", cjson.encode(upsconf), "cache: ", cache_status)
		if not upsconf or not upsconf["cache"] then return end
		for _, r in ipairs(upsconf["cache"]) do
			if r["url"] and str_find(ngx_var.uri, r["url"], 1, true) ~= nil then
				cache_time = r["time"]
			elseif r["file"] and str_find(r["file"], _M.get_file_ext(ngx_var.uri), 1, true) ~= nil then
				cache_time = r["time"]
			end
		end
	    if cache_time > 0 and (cache_status == "MISS" or cache_status == "EXPIRED") then
            local cache_data = http_cache.get_metadata()
            local new_expire = ngx.time() + cache_time 

            if cache_data and cache_data["valid_sec"] then
                http_cache.set_metadata({ valid_sec = new_expire,
                                          fcn = { valid_sec = new_expire,
                                          expire = new_expire } })
            end
        end	
	end,
}

function _M.bootstrap()
	for _, state in ipairs(_M.events) do
		_M.states[state]()
	end
end

return _M
