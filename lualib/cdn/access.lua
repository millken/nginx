local cjson = require "cjson"
local cookie = require "cdn.cookie"
local config = require "cdn.config"
local log = require "cdn.log"

local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack
        
local ngx_var = ngx.var
local ngx_ctx = ngx.ctx
local ngx_re_find = ngx.re.find
local ngx_now = ngx.now
local ngx_exit = ngx.exit
local ngx_md5 = ngx.md5
local ngx_time = ngx.time
local ip_blacklist = ngx.shared.ip_blacklist
local ip_whitelist = ngx.shared.ip_whitelist
local req_iplist = ngx.shared.req_iplist
local req_metrics = ngx.shared.req_metrics

local client_ip = ngx_var.remote_addr
local cookies = cookie.get()
local COOKIE_NAME = "__waf_uid"
local COOKIE_KEY = "xg0j21"

if ip_whitelist:get(client_ip) ~= nil then
	if ip_whitelist:get(client_ip) >= ngx_now() then
		return
	end
end
if ip_blacklist:get(client_ip) ~= nil then
	if ip_blacklist:get(client_ip) >= ngx_now() then
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
end

local req_interval = 5
local req_key = "total_req"
local req_count, err = req_metrics:incr(req_key, 1)
if not req_count then
	req_metrics:add(req_key, 1, req_interval)
end

local ip_interval = 5
local ip_key = "total_ip"
local ok, err = req_iplist:incr(ip_key, 0)
if not ok then
--	req_iplist:flush_all()
	req_iplist:set(ip_key.."_time", ngx_time() + ip_interval, ip_interval)
    req_iplist:add(ip_key, 0, ip_interval)
end
local ttl = 0
local ip_val = req_iplist:get(ip_key.."_time")
if ip_val then
	ttl = ip_val - ngx_time()
end
if ttl > 0 then
	local ok, err = req_iplist:safe_add(client_ip, true, ttl)
	if ok then
		req_iplist:incr(ip_key, 1)
	end
end

local hd_interval = 5
local hd_key = ngx_var.http_host
local hd_count, err = req_metrics:incr(hd_key, 1)
if not hd_count then
	req_metrics:add(hd_key, 1, hd_interval)
end


log:info("ip total: ", req_iplist:get(ip_key), "(", ip_interval, "s)", 
"req total: ", req_metrics:get(req_key), "(", req_interval, "s)",
"http header total: ", req_metrics:get(hd_key), "(", hd_interval, "s)", ngx_time()
)
-- identify if request is page or resource
if ngx_re_find(ngx.var.uri, "\\.(bmp|css|gif|ico|jpe?g|js|png|swf)$", "ioj") then
    ngx_ctx.cdn_rtype = "resource"
else
    ngx_ctx.cdn_rtype = "page"
end

-- if QPS is exceed 5, start cookie challenge
if req_count and req_count > 20 then
	local user_id = ngx_md5(zone_key)
    if cookies[COOKIE_NAME] ~= user_id then
        cookie.challenge(COOKIE_NAME, user_id)
        return
    end
end
