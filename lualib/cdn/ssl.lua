local ssl = require "ngx.ssl"
local log = require "cdn.log"
local hosts = require "cdn.hosts"

local ngx = ngx
local ngx_var = ngx.var

local settings = ngx.shared.settings

local _M = {
    _VERSION = '0.01',
}

local function validate_cert(v)
  local der = ssl.cert_pem_to_der(v)
  if der then
    return true, nil, { _cert_der_cache = base64.encode(der) }
  end
  return false, "Invalid SSL certificate"
end

local function validate_key(v)
  local der = ssl.priv_key_pem_to_der(v)
  if der then
    return true, nil, { _key_der_cache = base64.encode(der) }
  end
  return false, "Invalid SSL certificate key"
end

local function is_https()
  local result = ngx_var.scheme:lower() == "https"
  return result
end

function _M.bootstrap()
    local server_name = ssl.server_name()
    if server_name == nil then
        log:info("sni not present")
        ngx.say("sni not present")
        return ngx.exit(201)
    end
    log:debug("SNI server_name :", server_name)
    --server_name = "ssl"
    local key, setting = hosts.get_config(server_name)
    if setting == nil or setting["https"] == nil then
        return ngx.exit(404)
    end
    local ssl_key = setting["https"]["key"] or "";
    local key_data = ngx.decode_base64(ssl_key);
    if not key_data then
        return ngx.exit(404)
    end
    local ssl_cert = setting["https"]["cert"] or "";
    local cert_data = ngx.decode_base64(ssl_cert);
    if not cert_data then
        return ngx.exit(404)
    end

    ssl.clear_certs()

    local ok, err = ssl.set_der_priv_key(key_data)
    if not ok then
        log:error("failed to set DER priv key: ", err)
        return
    end
	local ok, err = ssl.set_der_cert(cert_data)
	if not ok then
	    log:error("failed to set DER cert: ", err)
	    return
	end
end

return _M
