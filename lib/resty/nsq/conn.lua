

local nsq_queue    = require "resty.nsq.queue"
local bit          = require "bit"
local cjson        = require "cjson"

local strsub       = string.sub
local byte         = string.byte
local char         = string.char
local concat       = table.concat
local encode       = cjson.encode
local decode       = cjson.decode
local band         = bit.band
local bor          = bit.bor
local rshift       = bit.rshift
local lshift       = bit.lshift
local tcp          = ngx.socket.tcp
local ngx_log      = ngx.log
local ERR          = ngx.ERR
local w_exiting    = ngx.worker.exiting
local type         = type
local pairs        = pairs
local unpack       = unpack
local setmetatable = setmetatable
local tonumber     = tonumber
local tostring     = tostring
local rawget       = rawget
local pow          = math.pow
local floor        = math.floor


local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end


local _M = new_tab(0, 19)

_M._VERSION = '0.01'
_M.new_tab = new_tab


local frame_type_response = 0
local frame_type_error    = 1
local frame_type_message  = 2

local heartbeat = 30


local _user_agent = "lua-resty-lua/" .. _M._VERSION
local _clientid   = "lua-resty-lua-client"
local _hostname   = "lua-resyt-lua-hostname"


local mt = { __index = _M }


local function _num_2_byte4(n)
    return char(band(rshift(n, 24), 0xff),
                band(rshift(n, 16), 0xff),
                band(rshift(n, 8), 0xff),
                band(n, 0xff))
end


local _2pow56 = pow(2, 56)
local _2pow48 = pow(2, 48)
local _2pow40 = pow(2, 40)
local _2pow32 = pow(2, 32)
local _2pow24 = pow(2, 24)
local _10pow9 = pow(10, 9)

local function _byte4_2_num(b1, b2, b3, b4)
    return b1 * _2pow24 + bor(lshift(b2, 16), bor(lshift(b3, 8), b4))
end


-- we use timestamp in second
-- NOTICE: lua only has 52 byte for int
local function _int64_2_timestamp(b1, b2, b3, b4, b5, b6, b7, b8)
    return floor((b1 * _2pow56 + b2 * _2pow48 + b3 * _2pow40 + b4 * _2pow32
                  + _byte4_2_num(b5, b6, b7, b8)) / _10pow9)
end


function _M.new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    return setmetatable({
        sock       = sock,
        resp_queue = nsq_queue:new(10),
        msg_queue  = nsq_queue:new(500),
        exiting    = false,
    }, mt)
end


local function close(self)
    return self.sock:close()
end
_M.close = close


function _M.connect(self, addr, port, config)
    if config.read_timeout
       and config.heartbeat
       and config.read_timeout < config.heartbeat
    then
        error("heartbeat interval should less than read_timeout")
    end

    local sock = self.sock

    local ret, err = sock:connect(addr, port)
    if not ret then
        return nil, err
    end

    local connect_timeout = (config.connect_timeout or 10) * 1000
    local send_timeout = (config.send_timeout or 10) * 1000
    local read_timeout = (config.read_timeout or 35) * 1000

    sock:settimeouts(connect_timeout, send_timeout, read_timeout)

    local bytes, err = sock:send("  V2")
    if not bytes then
        return nil, err
    end

    return ret
end


local function _read_reply(self)
    if self.fatal then
        return nil, nil, "fatal error already happened"
    end

    local sock = self.sock

    local data, err = sock:receive(8)
    if not data then
        if err == "timeout" then
            sock:close()
        end

        self.fatal = true
        return nil, nil, err
    end

    local size = _byte4_2_num(byte(data, 1, 4)) - 4 -- length of frame_type
    local frame_type = _byte4_2_num(byte(data, 5, 8))

    data, err = sock:receive(size)
    if not data then
        if err == "timeout" then
            sock:close()
        end

        self.fatal = true
        return nil, nil, err
    end

    -- ngx_log(ERR, "recv: ", data)

    if frame_type == frame_type_response then
        if strsub(data, 1, 1) == "{" then
            data = decode(data)
        end

        return data, frame_type
    end

    if frame_type == frame_type_error then
        return nil, frame_type, data
    end

    if frame_type == frame_type_message then
        local timestamp = _int64_2_timestamp(byte(data, 1, 8))

        return {
            timestamp = timestamp,
            id        = strsub(data, 11, 26),
            data      = strsub(data, 27), -- 8 + 2 +16
        }, frame_type
    end

    self.fatal = true
    return nil, nil, "unkowned type"
end
_M.read = _read_reply


local function _do_cmd(self, params, body, unrecv)
    if self.fatal then
        return nil, "fatal error already happened"
    end

    local sock = self.sock

    local req = {
        concat(params, " "),
        "\n",
    }

    if body then
        req[3] = _num_2_byte4(#body)
        req[4] = body
    end

    local bytes, err = sock:send(req)
    if not bytes then
        self.fatal = true

        return nil, err
    end

    if unrecv then
        return true
    end

    if self.read_looping then
        return self.resp_queue:pop(heartbeat)
    end

    local data, typ, err = _read_reply(self)
    if typ == frame_type_message then
        self.fatal = true
        return nil, "return message before read_looping"
    end

    return data, err
end


function _M.identify(self, config)
    local client = {
	    ["client_id"] = config.clientid or _clientid,
	    ["hostname"] = config.hostname or _user_agent,
	    ["user_agent"] = _user_agent,
	    ["tls_v1"] = false,
	    ["feature_negotiation"] = true,
		["heartbeat_interval"] = (config.heartbeat or heartbeat) * 1000,
	    ["sample_rate"] = 0,
	    -- ["deflate"] = config.deflate,
	    -- ["deflate_level"] = config.deflate_level,
	    -- ["snappy"] = config.snappy,
	    -- ["output_buffer_size"] = config.output_buffer_size,
		-- ["output_buffer_timeout"] = -1,
	    -- ["msg_timeout"] = config.msg_timeout,
    }

    return _do_cmd(self, { "IDENTIFY" }, encode(client))
end


function _M.auth(self, secret)
    return _do_cmd(self, { "AUTH" }, secret)
end


function _M.sub(self, topic, channel)
    return _do_cmd(self, { "SUB", topic, channel })
end


function _M.pub(self, topic, body)
    return _do_cmd(self, { "PUB", topic }, body)
end


function _M.fin(self, messageid)
    return _do_cmd(self, { "FIN", messageid }, nil, true)
end


function _M.req(self, messageid, timeout)
    return _do_cmd(self, { "REQ", messageid, timeout }, nil, true)
end


local function nop(self)
    return _do_cmd(self, { "NOP" }, nil, true)
end
_M.nop = nop


function _M.rdy(self, count)
    return _do_cmd(self, { "RDY", count }, nil, true)
end


function _M.cls(self, count)
    local ret, err = _do_cmd(self, { "CLS" }, nil, true)
    if ret then
        self._connected = false
    end

    return ret, err
end


function _M.message(self, timeout)
    timeout = tonumber(timeout) or 5

    local ret, err = self.msg_queue:pop(timeout)
    if err == "timeout" and self.fatal then
        return nil, "fatal error already happened"
    end

    return ret, err
end


function _M.exit_loop(self)
    self.exiting = true
end


function _M.read_loop(self, lock)
    local sock = self.sock
    local resp_queue = self.resp_queue
    local msg_queue = self.msg_queue

    self.read_looping = true

    while not self.exiting and not w_exiting() do
        local data, typ, err = _read_reply(self)
        if typ == frame_type_message then
            msg_queue:push(data)

        elseif typ then
            if data == "_heartbeat_" then
                lock:wait(2 * heartbeat)
                nop(self) -- heartbeat
                lock:post(1)

            else
                resp_queue:push(data)
            end

        else
            self.read_looping = false
            return nil, err
        end
    end

    self.read_looping = false
    return nil, "exiting"
end


function _M.check_name(str)
    if not str
       or type(str) ~= "string"
       or #str > 64
       or #str < 1
    then
        return false
    end

    return true
end


return _M
