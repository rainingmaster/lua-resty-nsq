

local nsq_conn     = require "resty.nsq.conn"
local semaphore    = require "ngx.semaphore"

local new_tab      = nsq_conn.new_tab
local check_name   = nsq_conn.check_name
local ngx_spawn    = ngx.thread.spawn
local ngx_wait     = ngx.thread.wait
local type         = type
local pairs        = pairs
local unpack       = unpack
local setmetatable = setmetatable
local tonumber     = tonumber
local tostring     = tostring
local rawget       = rawget


local _M = new_tab(0, 8)

_M._VERSION = nsq_conn._VERSION


local mt = { __index = _M }


function _M.new(self)
    local c, err = nsq_conn:new()
    if not c then
        return nil, err
    end

    local write_lock, err = semaphore:new()
    if not write_lock then
        return nil, err
    end

    write_lock:post(1)

    return setmetatable({
        write_lock = write_lock,
        conn = c,
        connected = false,
    }, mt)
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


local function lock_wrap(self, funcname, ...)
    local retry = 1
    local ok, err = nil, "timeout"
    while err == "timeout" do
        ok, err = self.write_lock:wait(5)
        retry = retry + 1
        if retry > 10 then
            return nil, "lock failed"
        end
    end

    if not ok then
        return nil, err
    end

    local conn = self.conn
    local ret, err = conn[funcname](conn, ...)

    self.write_lock:post(1)

    return ret, err
end


function _M.close(self)
    local conn = self.conn

    if self.subscribed then
        lock_wrap(self, "cls")
        conn:exit_loop()

        ngx_wait(self.read_co)
    end

    return conn:close()
end


function _M.sub(self, topic, channel)
    if not check_name(topic) then
        error("bad topic")
        return
    end

    if not check_name(channel) then
        error("bad channel")
        return
    end

    if self.subscribed then
        return nil, "is subscribed"
    end

    local conn = self.conn

    local ret, err = conn:sub(topic, channel)
    if not ret then
        return nil, err
    end

    self.subscribed = true
    self.read_co = ngx_spawn(conn.read_loop, conn, self.write_lock)

    return ret
end


function _M.fin(self, id)
    if not id then
        error("bad params: id")
        return
    end

    if not self.subscribed then
        return nil, "has not subscribed"
    end

    return lock_wrap(self, "fin", id)
end


function _M.req(self, id, timeout)
    if not id then
        error("bad params: id")
        return
    end

    if not tonumber(timeout) then
        error("bad params: timeout")
        return
    end

    if not self.subscribed then
        return nil, "has not subscribed"
    end

    return lock_wrap(self, "req", id, timeout)
end


function _M.rdy(self, count)
    if not tonumber(count) then
        error("bad params: count")
        return
    end

    if not self.subscribed then
        return nil, "has not subscribed"
    end

    return lock_wrap(self, "rdy", count)
end


function _M.message(self, timeout)
    return self.conn:message(timeout)
end


return _M
