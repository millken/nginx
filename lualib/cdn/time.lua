local ffi = require("ffi")

ffi.cdef[[
	typedef long time_t;
 
 	typedef struct timeval {
		time_t tv_sec;
		time_t tv_usec;
	} timeval;
 
	int gettimeofday(struct timeval* t, void* tzp);
]]

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }
 
local gettimeofday_struct = ffi.new("timeval")

function _M.gettimeofday()
 	ffi.C.gettimeofday(gettimeofday_struct, nil)
 	return tonumber(gettimeofday_struct.tv_sec) * 1000000 + tonumber(gettimeofday_struct.tv_usec)
end

return _M
