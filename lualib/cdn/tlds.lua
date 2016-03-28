local config = require "cdn.config"
local log = require "cdn.log"
local cmsgpack = require "cmsgpack"
local lrucache_mod = require "resty.lrucache"
local lrucache, err = lrucache_mod.new(200)
if not lrucache then 
	error("failed to create the cache: " .. (err or "unknown"))	
end
local cached = ngx.shared.cached
local table = table
local string = string
local io = io
local ngx = ngx
local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local function split(s, re)
  local i1, ls = 1, { }
  if not re then re = '%s+' end
  if re == '' then return { s } end
  while true do
    local i2, i3 = s:find(re, i1)
    if not i2 then
      local last = s:sub(i1)
      if last ~= '' then table.insert(ls, last) end
      if #ls == 1 and ls[1] == '' then
        return  { }
      else
        return ls
      end
    end
    table.insert(ls, s:sub(i1, i2 - 1))
    i1 = i3 + 1
  end
end

function _M.get_tlds()
	local tlds = cached:get("tldsdb")
	local tmp = {}
	if 	not tlds then
		local tldpath = config:get("db.tld") 
		log:info("load effective_tld_names.dat : ", tldpath)
		local file = io.open(tldpath, "rb")
		if not file then 
			log:error("file not exists : ", tldpath)
			return nil 
		end
		while true do
			local line = file:read("*line")
			if line == nil then break end
			if line:sub(1, 2) == '//' or #line == 0 then
				--
			elseif line:sub(1, 1) == '*' then
			else
				tmp[line] = true
			end
		end
		--local content = file:read "*a"
		file:close()
		cached:set("tldsdb", cmsgpack.pack(tmp))
	end
	return cmsgpack.unpack(cached:get("tldsdb"))
end

function _M.domain(host)
	local result, state = lrucache:get(host)
	if result then
		return result
	end
	local node = _M.get_tlds() 
	local parts = split(host:lower(), "%.")
	local i1 = 1
	local re = "%."
	while true do
		local i3 = i1
		local i2 = host:find(re, i1)
		if not i2 then
			break
		end
		i1 = i2 + 1
		local s1 = host:sub(i3, i2-1)
		local s4 = host:sub(i1)
		if node[s4] then
			result = s1 .. "." .. s4
			break
		end
	end
	if result then
		lrucache:set(host, result)
	end
	return result
end

return _M
