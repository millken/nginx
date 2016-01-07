cdn
===
````
git clone git@github.com:millken/tengcdn.git  --recursive
````
````
git submodule init

git submodule add https://github.com/alibaba/tengine.git

git submodule update
````
==INSTALL google-perftools
````
wget http://download.savannah.gnu.org/releases/libunwind/libunwind-1.1.tar.gz
tar xf libunwind-1.1.tar.gz 
cd libunwind-1.1
./configure
make && make install
cd ../gperftools
./autogen.sh 
./configure
make && make install
ln -s /usr/local/lib/libtcmalloc_minimal.so.4 /lib64/
ldconfig
````

==INSTALL tengine
````
./configure \
--with-http_realip_module \
--with-http_concat_module=shared \
--with-http_sysguard_module=shared \
--with-http_limit_conn_module=shared \
--with-http_limit_req_module=shared \
--with-http_upstream_ip_hash_module=shared \
--with-http_upstream_least_conn_module=shared \
--with-http_upstream_session_sticky_module=shared \
--with-google_perftools_module \
--with-ld-opt='-ltcmalloc_minimal'
````

==INSTALL ngx_lua 
````
./objs/dso_tool -a=lua-nginx-module/
````

````
//luajit
wget http://luajit.org/download/LuaJIT-2.1.0-beta1.tar.gz
# export LUAJIT_LIB=/usr/local/lib
# export LUAJIT_INC=/usr/local/include/luajit-2.1/
````

````
Key: "site_server_name"

    like:

        1) "site_kevin1986.com"
        2) "site__wildcard_.kevin1986.com"

Value: Json string

    upstream: the upstream strings. support keepalive, weight ,etc. n
    server_type: 1 = wildcard server_name,  0 = static server_name
    wildname: the regex match string. wildcard server_name config only.

    like:

        wildcard config
        "{\"gzip\": \"on\", \"upstream\": \"server 127.0.0.1:8080;\", \"wildname\": \"^.*.kevin1986.com$\", \"server_type\": 1}"

        static config
        "{\"gzip\": \"on\", \"upstream\": \"server 127.0.0.1:8080;\", \"server_type\": 0}"
````
==LINK
https://github.com/Wiladams/LJIT2Sophia
https://github.com/openresty/lua-resty-core
https://github.com/pintsized/ledge
https://github.com/hamishforbes/lua-resty-upstream
https://github.com/lloydzhou/lua-resty-cache
https://github.com/Veallym0n/dynamic-nginx-config-loader

