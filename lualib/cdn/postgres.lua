local pg = require("resty.postgres")
local log = require "cdn.log"

local _M = {
    _VERSION = '0.01',
	db = nil,
}

function _M:get_connect()
	if self.db ~= nil then
		return true, self.db
	end

	local db = pg:new()
	db:set_timeout(3000)
	local ok, err = db:connect({host="127.0.0.1",port=5432, database="cdn",
                            user="postgres",password="admin",compact=false})
	if not ok then
		return false, "can not connect to postgreSQL: " .. err
	end
	self.db = db
	return true, self.db
end

function _M:query(sql)
	local ok, db = self:get_connect()
	if not ok then
		return false, db 
	end
	local res, err = db:query(sql)
	if not res then
		return false, err
	end
	return true, res
end

function _M:close()
	if self.db then
		self.db:set_keepalive(0,100)
		self.db = nil
	end
end

return _M
