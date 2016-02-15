local ngx_say = ngx.say
local _M = {
    _VERSION = '0.01',
}
local mt = { __index = _M }

function _M.version()
	if jit then
		ngx_say(jit.version)
	else
		ngx_say("Not LuaJIT!")
	end
end

 return _M
