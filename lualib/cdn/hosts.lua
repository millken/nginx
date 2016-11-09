local cmsgpack = require "cmsgpack"
local tlds = require "cdn.tlds"
local lrucache_mod = require "resty.lrucache"
local log = require "cdn.log"
local lrucache, err = lrucache_mod.new(500)
if not lrucache then 
	error("failed to create the cache: " .. (err or "unknown"))	
end


local ngx = ngx
local ngx_var = ngx.var
local ngx_re_find = ngx.re.find

local settings = ngx.shared.settings

local _M = {
    _VERSION = 0.02,
}

function _M.get_config(host)
	local key, value = nil, nil
	local setting, err = _M.get_setting(host)
	if setting == nil or type(setting) ~= "table" then
		return key, value
	end

	if setting[host] == nil then
		for k, v in pairs(setting) do
			local i = k:find("%*")
			if i then 
				local rek, n, err = ngx.re.gsub(k, "\\*", "(.*?)")
				local from, to, err = ngx_re_find(host, rek, "isjo")
				if from then
					key = k
					value = v
					break
				end
			end
		end
	else
		key = host
		value = setting[host]
	end	
	return key, value
end

function _M.get_setting(host)
	local topleveldomain = tlds.domain(host)
	if topleveldomain == nil then
		return nil, "failed to get tld: " .. host
	end
	local setting = lrucache:get(topleveldomain)
	if setting ~= nil then
		return setting, nil
	end
	local setting_json = settings:get(topleveldomain)
	if setting_json == nil then
		return nil, "failed to get setting: " .. topleveldomain
	end
	local setting = cmsgpack.unpack(setting_json)
	lrucache:set(topleveldomain, setting)
	return setting, nil

end

function _M.delete_cache(host)
	lrucache:delete(host)
end


return _M
