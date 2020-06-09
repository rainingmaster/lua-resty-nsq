

local bit          = require "bit"
local semaphore    = require "ngx.semaphore"

local setmetatable = setmetatable
local tonumber     = tonumber
local error        = error


local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end


local _M = new_tab(0, 4)

_M._VERSION = '0.01'
_M.new_tab = new_tab


-- we test here
local MAX_SIZE = 5000

local mt = { __index = _M }


function _M.new(self, size)
    size = tonumber(size) or 0
    if size < 1 or size > MAX_SIZE then
        error("bad params: size")
        return
    end

    local lock, err = semaphore.new()
    if not lock then
        error("new semaphore failed: ", err)
        return
    end

    return setmetatable({
        list  = new_tab(size, 0),
        size  = size,
        head  = nil,
        last  = 1,
        lock  = lock,
    }, mt)
end


local function pre_pos(size, pos)
    pos = pos - 1

    if pos < 1 then
        return size
    end

    return pos
end


local function next_pos(size, pos)
    pos = pos + 1

    if pos > size then
        return 1
    end

    return pos
end


function _M.pop(self, timeout)
    timeout = tonumber(timeout)
    if not timeout then
        error("bad params: timeout")
        return
    end

    local lock = self.lock
    local ok, err = lock:wait(timeout)
    if not ok then
        return nil, err
    end

    local head = self.head
    local ret = self.list[head]

    head = next_pos(self.size, head)
    if head == self.last then -- empty now
        head = nil
    end

    self.head = head

    return ret
end


function _M.push(self, val)
    local last = self.last
    local head = self.head

    if head == last then
        return nil, "fulled"
    end

    self.list[last] = val

    if not head then -- not empty now
        self.head = self.last
    end

    self.last = next_pos(self.size, last)
    self.lock:post(1)

    return true
end


return _M
