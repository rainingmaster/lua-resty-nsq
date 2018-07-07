Name
====

lua-resty-nsq - Lua nsq client driver for the ngx_lua based on the cosocket API

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Description](#description)
* [Synopsis](#synopsis)
* [Modules](#methods)
    * [resty.nsq.producer](#producer)
        * [Methods](#methods)
            * [new](#new)
            * [pub](#pub)
            * [nop](#nop)
            * [close](#close)
    * [resty.nsq.consumer](#consumer)
        * [Methods](#methods)
            * [new](#new)
            * [sub](#sub)
            * [rdy](#rdy)
            * [fin](#fin)
            * [req](#req)
            * [close](#close)
* [NSQ Authentication](#nsq-authentication)
* [Installation](#installation)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

Status
======

[![Build Status](https://www.travis-ci.org/rainingmaster/lua-resty-nsq.svg?branch=master)](https://www.travis-ci.org/rainingmaster/lua-resty-nsq)

This library is developing.

Description
===========

This Lua library is a NSQ client driver for the ngx_lua nginx module:

This Lua library takes advantage of ngx_lua's cosocket API, which ensures
100% nonblocking behavior.

Synopsis
========

```lua
    lua_package_path "/path/to/lua-resty-nsq/lib/?.lua;;";

    server {
        location /test {
            content_by_lua_block {
                local config = {
                    read_timeout = 3,
                    heartbeat = 1,
                }
                local producer = require "resty.nsq.producer"
                local consumer = require "resty.nsq.consumer"

                local cons = consumer:new()
                local prod = producer:new()

                local ok, err = cons:connect("127.0.0.1", 4150, config)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                local ok, err = prod:connect("127.0.0.1", 4150)
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
                    c:rdy(10)
                    local ret = cons:message()
                    ngx.say("sub success: ", require("cjson").encode(ret))
                end

                local co = ngx.thread.spawn(read, cons) -- read message in new thread
                ngx.thread.wait(co)

                ok, err = cons:close()
                if not ok then
                    ngx.say("failed to close: ", err)
                    return
                end
            }
        }
    }
```

[Back to TOC](#table-of-contents)

Modules
=======

[Back to TOC](#table-of-contents)

resty.nsq.producer
--------

[Back to TOC](#table-of-contents)

### Methods

[Back to TOC](#table-of-contents)

#### new

[Back to TOC](#table-of-contents)

#### pub

[Back to TOC](#table-of-contents)

resty.nsq.consumer
--------

[Back to TOC](#table-of-contents)

### Methods

[Back to TOC](#table-of-contents)

#### new

[Back to TOC](#table-of-contents)

Installation
====

export LUA_LIB_DIR=/path/to/lualib && make install

[Back to TOC](#table-of-contents)

TODO
====

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2018-2018, by rainingmaster.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========
* the ngx_lua module: https://github.com/openresty/lua-nginx-module/#readme
* the nsq wired protocol specification: https://nsq.io/clients/tcp_protocol_spec.html
* [the semaphore in openresty: ngx.sema](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/semaphore.md)
* [the thread in openresty: ngx.thread](https://github.com/openresty/lua-nginx-module#ngxthreadspawn)

[Back to TOC](#table-of-contents)

