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
NGINX=$PWD/nginx
TENGINE=$PWD/tengine
usage()
{
	echo "Usage: `basename $0` tengine|nginx"
}

buildNgx()
{
	cd $NGINX
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
	--add-module=../ext/headers-more-nginx-module \
	--add-module=../ext/echo-nginx-module \
	--add-module=../ext/nginx-sticky-module-ng \
	--add-module=../ext/ngx_http_ydwaf_module \
	--add-module=../ext/ngx_yd_single_ssl_module \
	--add-module=../ext/ngx_http_conn_statistics \
	--add-module=../ext/ccprotect \
	--add-module=../ext/ngx_http_process_coredump \
	--add-module=../ext/ngx_http_snap_js_module \
	--add-module=../ext/ngx_http_acl_module\
	--with-debug \
	--with-cc-opt="-O0"
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
