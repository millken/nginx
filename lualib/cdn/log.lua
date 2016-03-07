local logger = require "resty.logger"
local config = require "cdn.config"
local table_concat = table.concat
local ngx = ngx
local _M = {
    _VERSION = '0.01',
}
-- log level
local LVL_DEBUG = 1
local LVL_INFO  = 2
local LVL_ERROR = 3
local LVL_NONE  = 999

local mt = { __index = _M }

function _M.info(self, ... )
	if config:get('log.status') then
		local log_level = config:get('log.level') or LVL_NONE
		if log_level and log_level > LVL_INFO then return end

		local filer = config:get('log.file')
		if filer then
			filer:info(table_concat({...}))
		else
			ngx.log(ngx.INFO, ...)
		end
	end
end

function _M.debug(self, ... )
	if config:get('log.status') then
		local log_level = config:get('log.level') or LVL_NONE
		if log_level and log_level > LVL_DEBUG then return end

		local filer = config:get('log.file')
		if filer then
			filer:debug(table_concat({...}))
		else
			ngx.log(ngx.DEBUG, ...)
		end
	end
end

function _M.error(self, ... )
	if config:get('log.status') then
		local log_level = config:get('log.level') or LVL_NONE
		if log_level and log_level > LVL_ERROR then return end
	
		local filer = config:get('log.file')
		if filer then
			filer:error(table_concat({...}))
		else
			ngx.log(ngx.ERR, ...)
		end
	end
end
return _M
