local setmetatable = setmetatable
local error = error
local assert = assert
local require = require
local ipairs = ipairs
local pairs = pairs
local unpack = unpack
local tostring = tostring
local tonumber = tonumber
local type = type
local next = next
local table = table
local ngx = ngx
local cjson = require('cjson')
module(...)

_VERSION = '0.01'

local mt = { __index = _M }

local redis = require "resty.redis"
local h_util = require "httpmanager.header_util"

function new(self)
    local config = {
        origin_location = "/__httpmanager_origin",

        redis_database  = 0,
        redis_timeout   = 100,          -- Connect and read timeout (ms)
        redis_keepalive_timeout = nil,  -- Defaults to 60s or lua_socket_keepalive_timeout
        redis_keepalive_poolsize = nil, -- Defaults to 30 or lua_socket_pool_size
        redis_hosts = {
            { host = "127.0.0.1", port = 6379, socket = nil, password = nil }
        },
        redis_use_sentinel = false,
        redis_sentinels = {},

        keep_cache_for  = 86400 * 30,   -- Max time to Keep cache items past expiry + stale (sec)
        max_stale       = nil,          -- Warning: Violates HTTP spec
        stale_if_error  = nil,          -- Max staleness (sec) for a cached response on upstream error
        enable_collapsed_forwarding = false,
        collapsed_forwarding_window = 60 * 1000,   -- Window for collapsed requests (ms)
    }

    return setmetatable({ config = config, }, mt)
end

-- A safe place in ngx.ctx for the current module instance (self).
function ctx(self)
    local id = tostring(self)
    local ctx = ngx.ctx[id]
    if not ctx then
        ctx = {
        	rules = {},
            events = {},
            config = {},
            state_history = {},
            event_history = {},
            current_state = "",
            client_validators = {},
            response = {status = nil, body = "", header = {}},
            cache = {},
        }
        ngx.ctx[id] = ctx
    end
    return ctx
end

-- Set a config parameter
function config_set(self, param, value)
    if ngx.get_phase() == "init" then
        self.config[param] = value
    else
        self:ctx().config[param] = value
    end
end


-- Gets a config parameter.
function config_get(self, param)
    local p = self:ctx().config[param]
    if p == nil then
        return self.config[param]
    else
        return p
    end
end


function set_response(self, res, name)
    local name = name or "response"
    self:ctx()[name] = res
end


function get_response(self, name)
    local name = name or "response"
    return self:ctx()[name]
end

function bind(self, event, callback)
    local events = self:ctx().events
    if not events[event] then events[event] = {} end
    table.insert(events[event], callback)
end


function emit(self, event, res)
    local events = self:ctx().events
    for _, handler in ipairs(events[event] or {}) do
        if type(handler) == "function" then
            handler(res)
        end
    end
end


---------------------------------------------------------------------------------------------------
-- Actions. Functions which can be called on transition.
---------------------------------------------------------------------------------------------------
actions = {
    redis_connect = function(self)
        return self:redis_connect()
    end,
    redis_close = function(self)
        return self:redis_close()
    end,    
    set_http_service_unavailable = function(self)
        ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
        ngx.say("server is busy")
    end,    
    set_http_status_from_response = function(self)
        local res = self:get_response()
        if res.status then
            ngx.status = res.status
        else
            res.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        end
    end,   
    read_cache = function(self)
        local res = self:read_from_cache() 
        self:set_response(res)
    end,  
    fetch = function(self)
        local res = self:fetch_from_origin()
        if res.status ~= ngx.HTTP_NOT_MODIFIED then
            self:set_response(res)
        end
    end,       
    remove_client_validators = function(self)
        -- Keep these in case we need to restore them (after revalidating upstream)
        local client_validators = self:ctx().client_validators
        client_validators["If-Modified-Since"] = ngx.var.http_if_modified_since
        client_validators["If-None-Match"] = ngx.var.http_if_none_match

        ngx.req.set_header("If-Modified-Since", nil)
        ngx.req.set_header("If-None-Match", nil)
    end,

    restore_client_validators = function(self)
        local client_validators = self:ctx().client_validators
        ngx.req.set_header("If-Modified-Since", client_validators["If-Modified-Since"])
        ngx.req.set_header("If-None-Match", client_validators["If-None-Match"])
    end,    
    set_http_not_modified = function(self)
        ngx.status = ngx.HTTP_NOT_MODIFIED
    end,    
    save_to_cache = function(self)
        local res = self:get_response()
        return self:save_to_cache(res)
    end,    
}
---------------------------------------------------------------------------------------------------
-- Event transition table.
---------------------------------------------------------------------------------------------------
-- Use "begin" to transition based on an event. Filter transitions by current state "when", and/or
-- any previous state "after", and/or a previously fired event "in_case", and run actions using
-- "but_first". Transitions are processed in the order found, so place more specific entries for a
-- given event before more generic ones.
---------------------------------------------------------------------------------------------------
events = {
    -- Initial transition. Let's find out if we're connecting via Sentinel.
    init = {
        { begin = "connecting_to_redis" },
    },
    -- We're connected! Let's get on with it then... First step, analyse the request.
    redis_connected = {
        { begin = "checking_request" },
    },    
    -- We failed to connect to redis. If we were trying a master at the time, lets give the
    -- slaves a go. Otherwise, bail.
    redis_connection_failed = {
        { begin = "exiting", but_first = "set_http_service_unavailable" },
    },    
    -- The request accepts cache. If we've already validated locally, we can think about serving.
    -- Otherwise we need to check the cache situtation.
    cache_accepted = {
        {  when = "revalidating_locally", begin = "preparing_response" },
        { begin = "checking_cache" },   
    }, 
    -- We don't know anything about this URI, so we've got to see about fetching. 
    cache_missing = {
        { begin = "fetching" },
    },    
    -- We have a response we can use. If we've already served (we are doing background work) then 
    -- just exit. If it has been prepared and we were not_modified, then set 304 and serve.
    -- If it has been prepared, set status accordingly and serve. If not, prepare it.
    response_ready = {
        { in_case = "served", begin = "exiting" },
        { in_case = "forced_cache", begin = "serving", but_first = "add_disconnected_warning"},
        { when = "preparing_response", in_case = "not_modified",
            begin = "serving", but_first = "set_http_not_modified" },
        { when = "preparing_response", begin = "serving", 
            but_first = "set_http_status_from_response" },
        { begin = "preparing_response" },
    },    
    -- We've fetched and got a response. We don't know about it's cacheabilty yet, but we must
    -- "update" in one form or another.
    response_fetched = {
        { begin = "updating_cache" },
    },    
    -- We deduced that the new response can cached. We always "save_to_cache". If we were fetching
    -- as a surrogate (collapsing) make sure we tell any others concerned. If we were performing
    -- a background revalidate (having served stale), we can just exit. Otherwise go back through
    -- validationg in case we can 304 to the client.
    response_cacheable = {
        { after = "fetching_as_surrogate", begin = "publishing_collapse_success", 
            but_first = "save_to_cache" },
        { after = "revalidating_in_background", begin = "exiting", 
            but_first = "save_to_cache" },
        { begin = "considering_local_revalidation", 
            but_first = "save_to_cache" },
    },
    -- This request doesn't accept cache, so we need to see about fetching directly.
    cache_not_accepted = {
        { begin = "checking_can_fetch" },
    },
    -- We've deduced that the new response cannot be cached. Essentially this is as per
    -- "response_cacheable", except we "delete" rather than "save", and we don't try to revalidate.
    response_not_cacheable = {
        { after = "fetching_as_surrogate", begin = "publishing_collapse_failure",
            but_first = "delete_from_cache" },
        { after = "revalidating_in_background", begin = "exiting", 
            but_first = "delete_from_cache" },
        { begin = "preparing_response", but_first = "delete_from_cache" },
    },
    -- We have a (not expired) cache entry. Lets try and validate in case we can exit 304.
    cache_valid = {
        { when = "checking_cache", begin = "considering_revalidation" },
    },
    -- We can validate locally, so do it. This doesn't imply it's valid, merely that we have
    -- the correct parameters to attempt validation.
    can_revalidate_locally = {
        { begin = "revalidating_locally" },
    },
    -- We have sent the response. If it was stale, we go back around the fetching path
    -- so that a background revalidation can occur unless the upstream errored. Otherwise exit.
    served = {
        { in_case = "upstream_error", begin = "exiting" },
        { in_case = "collapsed_forwarding_upstream_error", begin = "exiting" },
        { when = "serving_stale", begin = "checking_can_fetch" },
        { begin = "exiting" },
    },
    -- Standard non-conditional request.
    no_validator_present = {
        { begin = "preparing_response" },
    },   
    -- The response has not been modified against the validators given. We'll exit 304 if we can
    -- but go via preparing_response in case of ESI work to be done.
    not_modified = {
        { when = "revalidating_locally", begin = "preparing_response" },
    },    
}
states = {

    connecting_to_redis = function(self)
        local hosts = self:config_get("redis_hosts")
        local ok, err, redis = self:redis_connect(hosts)
        if not ok then
            ngx.log(ngx.ERR, "Failed to connect redis server:", err)
            return self:e "redis_connection_failed"
        else
            self:ctx().redis = redis
            return self:e "redis_connected"
        end
    end,
    checking_request = function(self)
        if self:request_accepts_cache() then
            return self:e "cache_accepted"
        else
            return self:e "cache_not_accepted"
        end
    end,    
    preparing_response = function(self)
        return self:e "response_ready"
    end,    
    checking_cache = function(self)
        local res = self:get_response()

        if not res then
            return self:e "cache_missing"
        elseif self:has_expired() then
            return self:e "cache_expired"
        else
            return self:e "cache_valid"
        end
    end,    
    fetching = function(self)
        local res = self:get_response()

        if res.status >= 500 then
            return self:e "upstream_error"
        elseif res.status == ngx.HTTP_NOT_MODIFIED then
            return self:e "response_ready"
        else
            return self:e "response_fetched"
        end
    end,
    checking_can_fetch = function(self)
        ngx.exit(451)
    end,    
    updating_cache = function(self)
        if ngx.req.get_method() ~= "HEAD" then
            local res = self:get_response()
            if self:is_cacheable() then
                return self:e "response_cacheable"
            else
                return self:e "response_not_cacheable"
            end
        else
            return self:e "response_body_missing"
        end
    end,     
    considering_local_revalidation = function(self)
        if self:can_revalidate_locally() then
            return self:e "can_revalidate_locally"
        else
            return self:e "no_validator_present"
        end
    end,    
    considering_revalidation = function(self)
        if self:can_revalidate_locally() then
            return self:e "can_revalidate_locally"
        else
            return self:e "no_validator_present"
        end
    end,    
    preparing_response = function(self)
        return self:e "response_ready"
    end,  
    serving = function(self)
        self:serve()
        return self:e "served"
    end,    
    revalidating_locally = function(self)
        if self:is_valid_locally() then
            return self:e "not_modified"
        else
            return self:e "modified"
        end
    end,     

    exiting = function(self)
        ngx.exit(ngx.status)
    end,     
}
---------------------------------------------------------------------------------------------------
-- Pre-transitions. Actions to always perform before transitioning.
---------------------------------------------------------------------------------------------------
pre_transitions = {
    exiting = { "redis_close" },
    checking_cache = { "read_cache" },
    -- Never fetch with client validators, but put them back afterwards.
    fetching = {
        "fetch", "restore_client_validators"
    },
    -- Use validators from cache when revalidating upstream, and restore client validators
    -- afterwards.
    revalidating_upstream = {
        "remove_client_validators",
        "add_validators_from_cache",
        "fetch",
        "restore_client_validators"
    },
    -- Need to save the error response before reading from cache in case we need to serve it later
    considering_stale_error = {
        "stash_error_response",
        "read_cache"
    },
    -- Restore the saved response and set the status when serving an error page
    serving_upstream_error = {
        "restore_error_response",
        "set_http_status_from_response"
    },
}

-- Transition to a new state.
function t(self, state)
    local ctx = self:ctx()

    -- Check for any transition pre-tasks
    local pre_t = self.pre_transitions[state]

    if pre_t then
        for _,action in ipairs(pre_t) do
            ngx.log(ngx.DEBUG, "#a: ->pre_transitions[" .. state .. ']->' .. action)
            self.actions[action](self)
        end
    end

    ngx.log(ngx.DEBUG, "#t: " .. state)

    ctx.state_history[state] = true
    ctx.current_state = state
    return self.states[state](self)
end


-- Process state transitions and actions based on the event fired.
function e(self, event)
    ngx.log(ngx.DEBUG, "#e: " .. event)

    local ctx = self:ctx()
    ctx.event_history[event] = true

    -- It's possible for states to call undefined events at run time. Try to handle this nicely.
    if not self.events[event] then
        ngx.log(ngx.CRIT, event .. " is not defined.")
        ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        self:t("exiting")
    end
    
    for _, trans in ipairs(self.events[event]) do
        local t_when = trans["when"]
        if t_when == nil or t_when == ctx.current_state then
            local t_after = trans["after"]
            if not t_after or ctx.state_history[t_after] then 
                local t_in_case = trans["in_case"]
                if not t_in_case or ctx.event_history[t_in_case] then
                    local t_but_first = trans["but_first"]
                    if t_but_first then
                        ngx.log(ngx.DEBUG, "#a: " .. t_but_first)
                        self.actions[t_but_first](self)
                    end

                    return self:t(trans["begin"])
                end
            end
        end
    end
end


function cache_key(self)
    if not self:ctx().cache_key then
        -- Generate the cache key. The default spec is:
        -- ledge:cache_obj:http:example.com:/about:p=3&q=searchterms
        local key_spec = self:config_get("cache_key_spec") or {
            ngx.var.scheme,
            ngx.var.host,
            ngx.var.uri,
            ngx.var.args,
        }
        table.insert(key_spec, 1, "cache_obj")
        table.insert(key_spec, 1, "ledge")
        self:ctx().cache_key = table.concat(key_spec, ":")
    end
    return self:ctx().cache_key
end


function fetching_key(self)
    return self:cache_key() .. ":fetching"
end

-- Fetches a resource from the origin server.
function fetch_from_origin(self)
    local res = {status = nil, body = "", header = {}}

    local method = ngx['HTTP_' .. ngx.req.get_method()]
    -- Unrecognised request method, do not proxy
    if not method then
        res.status = ngx.HTTP_METHOD_NOT_IMPLEMENTED
        return res
    end

    ngx.req.read_body() -- Must read body into lua when passing options into location.capture
    local origin = ngx.location.capture(self:config_get("origin_location")..relative_uri(), {
        method = method
    })

    res.status = origin.status
    -- Merge headers in rather than wipe out the res.headers table)
    for k,v in pairs(origin.header) do
        res.header[k] = v
    end
    res.body = origin.body

    if res.status < 500 then
        -- http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.18
        -- A received message that does not have a Date header field MUST be assigned
        -- one by the recipient if the message will be cached by that recipient
        if not res.header["Date"] or not ngx.parse_http_time(res.header["Date"]) then
            ngx.log(ngx.WARN, "no Date header from upstream, generating locally")
            res.header["Date"] = ngx.http_time(ngx.time())
        end
    end

    -- A nice opportunity for post-fetch / pre-save work.
    --self:emit("origin_fetched", res)

    return res
end


function save_to_cache(self, res)
    self:emit("before_save", res)

    -- These "hop-by-hop" response headers MUST NOT be cached:
    -- http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.1
    local uncacheable_headers = {
        --"Connection",
        --"Keep-Alive",
        "Proxy-Authenticate",
        "Proxy-Authorization",
        "TE",
        "Trailers",
        --"Transfer-Encoding",
        "Upgrade",

        -- We also choose not to cache the content length, it is set by Nginx
        -- based on the response body.
        --"Content-Length",
    }

    -- Also don't cache any headers marked as Cache-Control: (no-cache|no-store|private)="header".
    if res.header["Cache-Control"] and res.header["Cache-Control"]:find("=") then
        local patterns = { "no%-cache", "no%-store", "private" }
        for _,p in ipairs(patterns) do
            for h in res.header["Cache-Control"]:gmatch(p .. "=\"?([%a-]+)\"?") do
                table.insert(uncacheable_headers, h)
            end
        end
    end

    -- Utility to search in uncacheable_headers.
    local function is_uncacheable(t, h)
        for _, v in ipairs(t) do
            if v:lower() == h:lower() then
                return true
            end
        end
        return nil
    end

    -- Turn the headers into a flat list of pairs for the Redis query.
    local h = {}

    for header,header_value in pairs(res.header) do
        if not is_uncacheable(uncacheable_headers, header) then
        	
            if type(header_value) == 'table' then
                -- Multiple headers are represented as a table of values
                for i = 1, #header_value do
                    table.insert(h, 'h:'..i..':'..header)
                    table.insert(h, header_value[i])
                end
            else
            	--ngx.say(header.."\n")
                table.insert(h, 'h:'..header)
                table.insert(h, header_value)
            end
        end
    end

    local redis = self:ctx().redis

    -- Save atomically
    redis:multi()

    -- Delete any existing data, to avoid accidental hash merges.
    redis:del(cache_key(self))

    local ttl = 60
    local expires = ttl + ngx.time()
    local uri = full_uri()

    redis:hmset(cache_key(self),
        'body', res.body,
        'status', res.status,
        'uri', uri,
        'expires', expires,
        'generated_ts', ngx.parse_http_time(res.header["Date"]),
        'saved_ts', ngx.time(),
        unpack(h)
    )

    redis:expire(cache_key(self), ttl + tonumber(self:config_get("keep_cache_for")))

    -- Add this to the uris_by_expiry sorted set, for cache priming and analysis
    redis:zadd('ledge:uris_by_expiry', expires, uri)

    -- Run transaction
    if redis:exec() == ngx.null then
        ngx.log(ngx.ERR, "Failed to save cache item")
    end
end


function delete_from_cache(self)
    return self:ctx().redis:del(self:cache_key())
end


function expire(self)
    local cache_key = self:cache_key()
    local redis = self:ctx().redis
    if redis:exists(cache_key) == 1 then
        redis:hset(cache_key, "expires", tostring(ngx.time() - 1))
        return true
    else
        return false
    end
end


-- Tries hosts in the order given, and returns a redis connection (which may not be connected).
function redis_connect(self, hosts)
    local redis = redis:new()

    local timeout = self:config_get("redis_timeout")
    if timeout then
        redis:set_timeout(timeout)
    end

    local ok, err

    for _, conn in ipairs(hosts) do
        ok, err = redis:connect(conn.socket or conn.host, conn.port or 0)
        if ok then 
            -- Attempt authentication.
            local password = conn.password
            if password then
                ok, err = redis:auth(password)
            end

            -- redis:select always returns OK
            local database = self:config_get("redis_database")
            if database > 0 then
                redis:select(database)
            end

            break -- We're done
        end
    end

    return ok, err, redis
end


-- Close and optionally keepalive the redis (and sentinel if enabled) connection.
function redis_close(self)
    local redis = self:ctx().redis
    local sentinel = self:ctx().sentinel
    if redis then
        self:_redis_close(redis)
    end
    if sentinel then
        self:_redis_close(sentinel)
    end
end


function _redis_close(self, redis)
    -- Keep the Redis connection based on keepalive settings.
    local ok, err = nil
    local keepalive_timeout = self:config_get("redis_keepalive_timeout")
    if keepalive_timeout then
        if self:config_get("redis_keepalive_pool_size") then
            ok, err = redis:set_keepalive(keepalive_timeout, 
                self:config_get("redis_keepalive_pool_size"))
        else
            ok, err = redis:set_keepalive(keepalive_timeout)
        end
    else
        ok, err = redis:set_keepalive()
    end

    if not ok then
        ngx.log(ngx.WARN, "couldn't set keepalive, "..err)
    end
end

function add_cache_rule(self, rule)
    table.insert(self:ctx().rules, rule)
end

function run(self)
	ngx.log(ngx.DEBUG, "httpcache run :".. ngx.var.uri)
	local rules = self:ctx().rules or 0
	if #rules == 0 then
		ngx.exit(451)
	end
    self:e "init"
end

function relative_uri()
    return ngx.var.uri .. ngx.var.is_args .. (ngx.var.query_string or "")
end


function full_uri()
    return ngx.var.scheme .. '://' .. ngx.var.host .. relative_uri()
end

function is_static_cache(self)
    local status = false
    for _,r in ipairs(self:ctx().rules) do
        if r["file_ext"] and h_util.header_has_directive(ngx.var.uri, h_util.get_file_ext(ngx.var.uri)) then
            if r["static"] and r["static"] == true then status = true end
            self:ctx().cache = {static=r["static"] or false,time=r["time"] or 0}
        end
        ngx.log(ngx.DEBUG, cjson.encode(r) ..cjson.encode(self:ctx().cache) .. h_util.get_file_ext(ngx.var.uri))
    end
    return status
end

function request_accepts_cache(self)
    -- check static cache
    if self:is_static_cache() then
        return true
    end
    -- Check for no-cache
    local h = ngx.req.get_headers()
    if h_util.header_has_directive(h["Pragma"], "no-cache")
       or h_util.header_has_directive(h["Cache-Control"], "no-cache")
       or h_util.header_has_directive(h["Cache-Control"], "no-store")
       or h_util.header_has_directive(h["X-Requested-With"], "XMLHttpRequest") then
        return false
    end

    return true
end

function visible_hostname()
    local name = ngx.var.visible_hostname or ngx.var.hostname
    local server_port = ngx.var.server_port
    if server_port ~= "80" and server_port ~= "443" then
        name = name .. ":" .. server_port
    end
    return name
end

function read_from_cache(self)
    local res = {status = nil, body = "", header = {}}
    -- Fetch from Redis
    local cache_parts, err = self:ctx().redis:hgetall(cache_key(self))
    if not cache_parts then
        ngx.log(ngx.ERR, "Failed to read cache item: " .. err)
        return nil
    end

    -- No cache entry for this key
    if #cache_parts == 0 then
        return nil
    end

    local ttl = nil
    local time_in_cache = 0
    local time_since_generated = 0

    -- The Redis replies is a sequence of messages, so we iterate over pairs
    -- to get hash key/values.
    for i = 1, #cache_parts, 2 do
        -- Look for the "known" fields
        if cache_parts[i] == "body" then
            res.body = cache_parts[i + 1]
        elseif cache_parts[i] == "uri" then
            res.uri = cache_parts[i + 1]
        elseif cache_parts[i] == "status" then
            res.status = tonumber(cache_parts[i + 1])
        elseif cache_parts[i] == "expires" then
            res.remaining_ttl = tonumber(cache_parts[i + 1]) - ngx.time()
        elseif cache_parts[i] == "saved_ts" then
            time_in_cache = ngx.time() - tonumber(cache_parts[i + 1])
        elseif cache_parts[i] == "generated_ts" then
            time_since_generated = ngx.time() - tonumber(cache_parts[i + 1])
         else
            -- Unknown fields will be headers, starting with "h:" prefix.
            local header = cache_parts[i]:sub(3)
            if header then
                if header:sub(2,2) == ':' then
                    -- Multiple headers, we also need to preserve the order?
                    local index = tonumber(header:sub(1,1))
                    header = header:sub(3)
                    if res.header[header] == nil then
                        res.header[header] = {}
                    end
                    res.header[header][index]= cache_parts[i + 1]
                else
                    res.header[header] = cache_parts[i + 1]
                end
            end
        end
    end

    -- Calculate the Age header
    if res.header["Age"] then
        -- We have end-to-end Age headers, add our time_in_cache.
        res.header["Age"] = tonumber(res.header["Age"]) + time_in_cache
    elseif res.header["Date"] then
        -- We have no advertised Age, use the generated timestamp.
        res.header["Age"] = time_since_generated
    end

    self:emit("cache_accessed", res)

    return res
end

function can_revalidate_locally(self)
    local req_h = ngx.req.get_headers()
    local req_ims = req_h["If-Modified-Since"]

    if req_ims then
        if not ngx.parse_http_time(req_ims) then
            -- Bad IMS HTTP datestamp, lets remove this.
            ngx.req.set_header("If-Modified-Since", nil)
        else
            return true
        end
    end

    if req_h["If-None-Match"] then
        return true
    end
    
    return false
end

function is_cacheable()
    -- body
    return true
end
function has_expired(self)
    return false
end


function serve(self)
    if not ngx.headers_sent then
        local res = self:get_response() -- or self:get_response("fetched")
        assert(res.status, "Response has no status.")

        local visible_hostname = visible_hostname()

        -- Via header
        local via = "1.1 " .. visible_hostname .. " (httpmanager/" .. _VERSION .. ")"
        local res_via = res.header["Via"]
        if  (res_via ~= nil) then
            res.header["Via"] = via .. ", " .. res_via
        else
            res.header["Via"] = via
        end

        -- X-Cache header
        -- Don't set if this isn't a cacheable response. Set to MISS is we fetched.
        local ctx = self:ctx()
        local state_history = ctx.state_history

        if not ctx.event_history["response_not_cacheable"] then
            local x_cache = "HIT from " .. visible_hostname
            if state_history["fetching"] or state_history["revalidating_upstream"] then
                x_cache = "MISS from " .. visible_hostname
            end

            local res_x_cache = res.header["X-Cache"]

            if res_x_cache ~= nil then
                res.header["X-Cache"] = x_cache .. ", " .. res_x_cache
            else
                res.header["X-Cache"] = x_cache
            end
        end

        self:emit("response_ready", res)

        if res.header then
            for k,v in pairs(res.header) do
                ngx.header[k] = v
            end
        end

        if res.status ~= 304 and res.body then
            ngx.print(res.body)
        end

        ngx.eof()
    end
end
function is_valid_locally(self)
    local req_h = ngx.req.get_headers()
    local res = self:get_response()

    local res_lm = res.header["Last-Modified"]
    local req_ims = req_h["If-Modified-Since"]

    if res_lm and req_ims then
        local res_lm_parsed = ngx.parse_http_time(res_lm)
        local req_ims_parsed = ngx.parse_http_time(req_ims)

        if res_lm_parsed and req_ims_parsed then
            if res_lm_parsed > req_ims_parsed then
                return false
            end
        end
    end

    if res.header["Etag"] and req_h["If-None-Match"] then
        if res.header["Etag"] ~= req_h["If-None-Match"] then
            return false
        end
    end

    return true
end
local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}


setmetatable(_M, class_mt)
