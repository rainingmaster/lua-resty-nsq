

local nsq_conn     = require "resty.nsq.conn"

local new_tab      = nsq_conn.new_tab
local check_name   = nsq_conn.check_name
local type         = type
local setmetatable = setmetatable
local tonumber     = tonumber
local tostring     = tostring
local rawget       = rawget


local _M = new_tab(0, 5)

_M._VERSION = nsq_conn._VERSION


local mt = { __index = _M }


function _M.new(self)
    local c, err = nsq_conn:new()
    if not c then
        return nil, err
    end

    return setmetatable({ conn = c, connected = false }, mt)
end


function _M.connect(self, addr, port, config)
    local conn = self.conn

    local ret, err
    repeat
        config = config or {}

        ret, err = conn:connect(addr, port, config)
        if not ret then
            break
        end

        ret, err = conn:identify(config)
        if not ret then
            break
        end

        if type(ret) == "table" and ret.auth_required then
            ret, err = conn:auth(config.secret or "")
            if not ret then
                break
            end
        end

        self.connected = true

        return ret, err
    until false

    conn:close()

    return nil, err 
end


function _M.close(self)
    local conn = self.conn
    self.connected = false

    return conn:close()
end


function _M.nop(self)
    return self.conn:nop()
end


function _M.pub(self, topic, message)
    if not check_name(topic) then
        error("bad topic")
        return
    end

    if type(message) ~= "string" then
        error("bad message")
        return
    end

    local conn = self.conn

    return conn:pub(topic, message)
end


return _M
