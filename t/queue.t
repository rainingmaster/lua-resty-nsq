# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/lua-resty-core/lib/?.lua;$pwd/lua-resty-lrucache/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
};


no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local nsq_queue = require "resty.nsq.queue"
            local queue = nsq_queue:new(10)

            local function test_pop(q)
                local ret = q:pop(0.1)
                if ret then
                    ngx.say(ret)
                end
            end

            local co = ngx.thread.spawn(test_pop, queue)

            ngx.sleep(0.01)
            queue:push("hello world")

            ngx.thread.wait(co)
        }
    }
--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]



=== TEST 2: empty and timeout
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local nsq_queue = require "resty.nsq.queue"
            local queue = nsq_queue:new(10)

            local ret, err = queue:pop(0.5)
            ngx.say(ret, ":", err)
        }
    }
--- request
GET /t
--- response_body
nil:timeout
--- no_error_log
[error]



=== TEST 3: full
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local nsq_queue = require "resty.nsq.queue"
            local queue = nsq_queue:new(10)

            for i = 1, 11 do
                local ret, err = queue:push("hello world" .. i)
                if not ret then
                    ngx.say(ret, ":", err, ", in ", i)
                end
            end
        }
    }
--- request
GET /t
--- response_body
nil:fulled, in 11
--- no_error_log
[error]



=== TEST 4: read and write
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local nsq_queue = require "resty.nsq.queue"
            local queue = nsq_queue:new(10)

            local function test_pop(q)
                for i = 1, 30 do
                    local ret, err = q:pop(0.01)
                    if ret then
                        ngx.say("get: ", ret)
                        -- ngx.log(ngx.ERR, "get: ", ret)
                    end
                end
            end

            local co = ngx.thread.spawn(test_pop, queue)

            for i = 1, 30 do
                local ret, err = queue:push("hello world: " .. i)
                if not ret then
                    ngx.say(ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                    -- ngx.log(ngx.ERR, ret, ":", err, ", in ", i)
                end

                if i == 5 then
                    ngx.sleep(0)
                elseif i == 11 then
                    ngx.sleep(0)
                elseif i == 25 then
                    ngx.sleep(0)
                end
            end

            ngx.thread.wait(co)
        }
    }
--- request
GET /t
--- response_body
get: hello world: 1
get: hello world: 2
get: hello world: 3
get: hello world: 4
get: hello world: 5
get: hello world: 6
get: hello world: 7
get: hello world: 8
get: hello world: 9
get: hello world: 10
get: hello world: 11
nil:fulled, in 22
nil:fulled, in 23
nil:fulled, in 24
nil:fulled, in 25
get: hello world: 12
get: hello world: 13
get: hello world: 14
get: hello world: 15
get: hello world: 16
get: hello world: 17
get: hello world: 18
get: hello world: 19
get: hello world: 20
get: hello world: 21
get: hello world: 26
get: hello world: 27
get: hello world: 28
get: hello world: 29
get: hello world: 30
--- no_error_log
[error]
