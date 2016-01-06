#!/bin/bash

if [ -n "$1" ]; then
	cmd=$1
else
	cmd=""
fi
if [ -n "$2" ]; then
	arg=$2
else
	arg=""
fi

PWD=$(cd "$(dirname "$0")"; pwd)
ROOT=$(dirname "$PWD")
PATCH=$ROOT/patch
NGINX=$ROOT/nginx
usage()
{
	echo "Usage: `basename $0` tengine|nginx"
}

buildNgx()
{
	cd $NGINX
	export LUAJIT_INC=/usr/local/luajit-2.0.1/include/luajit-2.0/
	export LUAJIT_LIB=/usr/local/luajit-2.0.1/lib/
./configure --prefix=/nginx   \
	--with-http_ssl_module \
	--without-http_fastcgi_module \
	--without-http_uwsgi_module \
	--without-http_scgi_module \
	--without-select_module \
	--without-poll_module \
	--without-http_geo_module \
	--without-http_memcached_module \
	--without-http_limit_req_module \
	--without-http_limit_conn_module \
	--without-mail_pop3_module \
	--without-mail_imap_module \
	--without-mail_smtp_module \
	--with-pcre \
	--add-module=../ngx_devl_kit \
	--add-module=../lua-nginx-module \
	--add-module=../ngx_http_dyups_module \
	--add-module=../lua-upstream-cache-nginx-module
	--with-debug \
	--with-cc-opt="-O0"
sed -i 's#-L/usr/local/luajit-2.0.1/lib/ -lluajit-5.1#/usr/local/lib/libluajit-5.1.a#' objs/Makefile #静态编译
sed -i 's#HTTP_AUX_FILTER_MODULES#HTTP_MODULES#' ../lua-upstream-cache-nginx-module/config #fix config
make
	
}

buildTengine()
{
pushd $TENGINE
./configure \
--without-http_fastcgi_module \
--without-http_uwsgi_module \
--without-http_scgi_module \
--without-select_module \
--without-poll_module \
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
--with-debug \
--with-cc-opt="-O0"
make && make install;
popd
}

resetNgx()
{
	cd $NGINX
	git clean -xfd
	git reset --hard
}

patchNgx()
{
	#patch something
	for file in $PATCH/$arg/*.patch ; do 
		cd $NGINX;
		patch -p1 < $file;
	done  
}

rpatchNgx()
{
	#reverse patch something
	for file in $PATCH/$arg/*.patch ; do 
		cd $NGINX;
		patch -R -p1 < $file;
	done  
}

if [ "$1" == "" ]; then
	buildNgx
	exit 0
fi

if [ "$1" == "-h" ]; then
  usage
  exit 0
fi

if [ "$cmd" = "tengine" ]; then
	buildTengine
	exit
fi

if [ "$1" == "nginx" ]; then
	buildReleaseNgx
	exit 0
fi
