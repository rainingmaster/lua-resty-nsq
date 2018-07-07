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

$ENV{TEST_NGINX_RESOLVER} = '114.114.114.114';
$ENV{TEST_NGINX_NSQ_PORT} ||= 4150;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: sub: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local config = {
                read_timeout = 3,
                heartbeat = 1,
            }
            local producer = require "resty.nsq.producer"
            local consumer = require "resty.nsq.consumer"

            local cons = consumer:new()
            local prod = producer:new()

            local ok, err = cons:connect("127.0.0.1", $TEST_NGINX_NSQ_PORT, config)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local ok, err = prod:connect("127.0.0.1", $TEST_NGINX_NSQ_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ok, err = prod:pub("new_topic", "hellow world!")
            if not ok then
                ngx.say("failed to pub: ", err)
                return
            end

            ok, err = prod:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end

            ok, err = cons:sub("new_topic", "new_channel")
            if not ok then
                ngx.say("failed to sub: ", err)
                return
            end

            local function read(c)
                c:rdy(1)
                local ret = cons:message()
                c:fin(ret.id)
                ngx.say("sub success: ", require("cjson").encode(ret))
            end

            local co = ngx.thread.spawn(read, cons)
            ngx.thread.wait(co)

            ok, err = cons:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body_like
sub success: \{"timestamp":(.*),"data":"hellow world!","id":"(.*)"\}
--- no_error_log
[error]
