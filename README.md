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

==LINK

https://github.com/openresty/lua-resty-core
https://github.com/pintsized/ledge
https://github.com/hamishforbes/lua-resty-upstream