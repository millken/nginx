local _M = { _VERSION = '1.0' }

local mt = { __index = _M }

function _M.new(self)
	local shared_memory = ngx.shared.itesty_limit
    return setmetatable({ memory = shared_memory }, mt)
end

function _M.reqs_per_range(self, zone, key, requests, range)
	range = range or 1
	local zone_key = zone .. ":" .. key .. ":" .. math.ceil (ngx.time()/range)
	ngx.log(ngx.INFO, ngx.time(), ", range :", math.ceil (ngx.time()/5) )
	self.memory:add(zone_key, 0, range)
	local cur_para = self.memory:incr(zone_key, 1)
	if cur_para > requests then
		return false
	end
	
	return true
end

function _M.rate( self, rate )
	ngx.var.limit_rate = rate or "0"
	return 
end

return _M
