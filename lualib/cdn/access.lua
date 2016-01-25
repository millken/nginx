local cjson = require "cjson"
local cookie = require "cdn.cookie"

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
        
local ngx_log = ngx.log
local ngx_var = ngx.var
local ngx_ctx = ngx.ctx
local ngx_re_find = ngx.re.find
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local ngx_exit = ngx.exit
local ngx_md5 = ngx.md5
local ngx_time = ngx.time
local blocked_iplist = ngx.shared.blocked_iplist
local req_metrics = ngx.shared.req_metrics

local client_ip = ngx.var.remote_addr
local cookies = cookie.get()
local COOKIE_NAME = "__waf_uid"
local COOKIE_KEY = "xg0j21"

if blocked_iplist:get(client_ip) ~= nil then
	if blocked_iplist:get(client_ip) >= ngx_now() then
		ngx_exit(444)
	end
end

local http_ua = ngx_var.http_user_agent
if not http_ua then
	ngx_exit(400)
end

local zone_interval = 3
local zone_key = client_ip .. ":" .. ngx_var.uri .. ":" .. math.ceil (ngx_time() / zone_interval)
local zone_count, err = req_metrics:incr(zone_key, 1)
if not zone_count then
	req_metrics:add(zone_key, 1, zone_interval)
	return
end

-- identify if request is page or resource
if ngx_re_find(ngx.var.uri, "\\.(bmp|css|gif|ico|jpe?g|js|png|swf)$", "ioj") then
    ngx_ctx.cdn_rtype = "resource"
else
    ngx_ctx.cdn_rtype = "page"
end

-- if QPS is exceed 5, start cookie challenge
if zone_count > 2 then
	local user_id = ngx_md5(zone_key)
    if cookies[COOKIE_NAME] ~= user_id then
        cookie.challenge(COOKIE_NAME, user_id)
        return
    end
end
