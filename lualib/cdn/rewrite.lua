local hosts = require "cdn.hosts"
local config = require "cdn.config"
local log = require "cdn.log"
local dyups = require "ngx.dyups"

local ipairs = ipairs

local ngx = ngx
local ngx_var = ngx.var

local upstream_cached = ngx.shared.upstream_cached

local _M = {
    _VERSION = 0.01,
	events = {"parse_proxy"},
}

_M.states = {
	parse_proxy = function()
		local host = ngx_var.host
		if ngx_var.ups == "" then return end
		local ups_key, ups_value, setting

		ups_key, setting = hosts.get_config(host)
		if ups_key == nil or setting["ups"] == nil then
			ngx.exit(404)
		end
		config:set("upsconf", setting)
		ups_value = setting["ups"]

		local ups_cache, _ = upstream_cached:get(ups_key)
		if not ups_cache then
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
		if setting["scheme"] ~= nil then
			ngx_var.ups_scheme = setting["scheme"]
		end
		ngx_var.ups = ups_key
	end,
}

function _M.bootstrap()
	for _, state in ipairs(_M.events) do
		_M.states[state]()
	end
end

return _M
