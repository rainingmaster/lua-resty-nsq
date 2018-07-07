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

=== TEST 1: pub: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local producer = require "resty.nsq.producer"
            local prod = producer:new()

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

            ngx.say("pub success!")
        }
    }
--- request
GET /t
--- response_body
pub success!
--- no_error_log
[error]



=== TEST 2: pub: bad topic
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local producer = require "resty.nsq.producer"
            local prod = producer:new()

            ok, err = pcall(prod.pub, prod, "", "hellow world!")
            if not ok then
                ngx.say("failed to pub: ", err)
                return
            end

            ngx.say("pub success!")
        }
    }
--- request
GET /t
--- response_body_like
bad topic
--- no_error_log
[error]



=== TEST 3: pub: bad message
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block{
            local producer = require "resty.nsq.producer"
            local prod = producer:new()

            ok, err = pcall(prod.pub, prod, "topic")
            if not ok then
                ngx.say("failed to pub: ", err)
                return
            end

            ngx.say("pub success!")
        }
    }
--- request
GET /t
--- response_body_like
bad message
--- no_error_log
[error]
