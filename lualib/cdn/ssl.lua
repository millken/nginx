local ssl = require "ngx.ssl"
local log = require "cdn.log"

local ngx = ngx
local ngx_var = ngx.var

local settings = ngx.shared.settings

local function is_https()
  local result = ngx_var.scheme:lower() == "https"
  return result
end

local _M = {
    _VERSION = '0.01',
}

function _M.bootstrap()
    local server_name = ssl.server_name()
    if server_name == nil then
        log:info("sni not present")
        return
    end
    ssl.clear_certs()
    log:debug("server_name :", server_name)
    --server_name = "ssl"
    local key_data = nil;
    local f = io.open(string.format("/home/github/tengcdn/conf/ssl/%s.der", server_name), "r")
    if f then
        key_data = f:read("*a")
        f:close()
    end
    local cert_data = nil;
    local f = io.open(string.format("/home/github/tengcdn/conf/ssl/%s.crt.der", server_name), "r")
    if f then
        cert_data = f:read("*a")
        f:close()
    end
    if key_data and cert_data then
        local ok, err = ssl.set_der_priv_key(key_data)
        if not ok then
            ngx.log(ngx.ERR, "failed to set DER priv key: ", err)
            return
        end
		local ok, err = ssl.set_der_cert(cert_data)
		if not ok then
		    ngx.log(ngx.ERR, "failed to set DER cert: ", err)
		    return
		end
    end
end

return _M
