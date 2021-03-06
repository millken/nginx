local cmsgpack = require "cmsgpack"
local tlds = require "cdn.tlds"
local lrucache_mod = require "resty.lrucache"
local log = require "cdn.log"
local lrudsc, err = lrucache_mod.new(500)
if not lrudsc then 
	error("failed to create the cache: " .. (err or "unknown"))	
end
local lrucache, err = lrucache_mod.new(500)
if not lrucache then 
	error("failed to create the cache: " .. (err or "unknown"))	
end

local ngx = ngx
local ngx_var = ngx.var
local ngx_re_find = ngx.re.find

local settings = ngx.shared.settings

local _M = {
    _VERSION = '0.01',
}

function _M.get_ups(host)
	local ups_key, ups_value
	local setting, err = _M.get_setting(host)
	if setting == nil then
		log:info("get_setting : ", err)
		return nil, nil
	end
	if setting[ngx_var.host] == nil then
		for k, v in pairs(setting) do
			local i = k:find("%*")
			if i then 
				local rek, n, err = ngx.re.gsub(k, "\\*", "(.*?)")
				local from, to, err = ngx_re_find(ngx_var.host, rek, "isjo")
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

function _M.get_ups_key(host)
	return lrucache:get(host)
end

function _M.get_setting(host)
	local topleveldomain = tlds.domain(host)
	if topleveldomain == nil then
		return nil, "failed to get tld: " .. host
	end
	local setting = lrudsc:get(topleveldomain)
	if setting ~= nil then
		return setting
	end
	local setting_json = settings:get(topleveldomain)
	if setting_json == nil then
		return nil, "failed to get setting: " .. topleveldomain
	end
	local setting = cmsgpack.unpack(setting_json)
	lrudsc:set(topleveldomain, setting)
	return setting, nil

end

function _M.delete_cache(host)
	lrudsc:delete(host)
end


return _M
