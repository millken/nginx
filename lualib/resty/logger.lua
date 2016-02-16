-- Copyright (C) 2013 YanChenguang (kedyyan)

local bit = require "bit"
local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_str = ffi.string
local C = ffi.C
local bor = bit.bor

local setmetatable = setmetatable
local localtime 	= ngx.localtime()
local ngx 			= ngx
local   tostring, ipairs, pairs, type, tonumber, next, unpack =
        tostring, ipairs, pairs, type, tonumber, next, unpack

ffi.cdef[[
int write(int fd, const char *buf, int nbyte);
int open(const char *path, int access, int mode);
int close(int fd);
]]

local O_RDWR   = 0X0002
local O_CREAT  = 0x0040
local O_APPEND = 0x0400
local S_IRWXU  = 0x01C0
local S_IRGRP  = 0x0020
local S_IROTH  = 0x0004

-- log level
local LVL_DEBUG = 1
local LVL_INFO  = 2
local LVL_ERROR = 3
local LVL_NONE  = 999

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

function _M.open(self, logfile)
	local log_level, log_fd = nil

	local level = LVL_NONE
	local fd = C.open(logfile, bor(O_RDWR, O_CREAT, O_APPEND), bor(S_IRWXU, S_IRGRP, S_IROTH)) 
	if fd == -1 then
		ngx.log(ngx.ERR, "open log file " .. logfile .. " failed, errno: " .. tostring(ffi.errno()))
	end
	return setmetatable({
		log_level = level,
		log_fd = fd,
	},mt)
end

function _M.set_level(self, level)
	self.log_level = level
end

function _M.debug(self, msg)
	if self.log_level > LVL_DEBUG then return end;

	local c = localtime .. " [DEBUG] " .. msg .. "\n";
	C.write(self.log_fd, c, #c);
end

function _M.info(self, msg)
	if self.log_level > LVL_INFO then return end;

	local c = localtime .. " [INFO] " .. msg .. "\n";
	C.write(self.log_fd, c, #c);
end


function _M.error(self, msg)
	if self.log_level > LVL_ERROR then return end;

	local c = localtime .. " [ERROR] " .. msg .. "\n";
	C.write(self.log_fd, c, #c);
end

return _M

