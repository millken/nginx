#!/bin/bash
if [ $(id -u) != "0" ]; then
	echo "Error: NO PERMISSION! Please login as root to install OpenCDN."
	exit 1
fi

get_char()
{
	SAVEDSTTY=`stty -g`
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2> /dev/null
	stty -raw
	stty echo
	stty $SAVEDSTTY
}

function get_system_basic_info()
{
	echo ""
	echo "Press any key to start install tengcdn , please wait ......"
	char=`get_char`

	IS_64=`uname -a | grep "x86_64"`
	if [ -z "${IS_64}" ]
	then
		CPU_ARC="i386"
	else
		CPU_ARC="x86_64"
	fi

	IS_5=`cat /etc/redhat-release | grep "5.[0-9]"`
	if [ -z "${IS_5}" ]
	then
		VER="6"
		rpm_ver="epel-release-6-8.noarch.rpm"
	else
		VER="5"
		rpm_ver="epel-release-5-4.noarch.rpm"
	fi
	setenforce 0
	rpm -ivh "http://dl.fedoraproject.org/pub/epel/${VER}/${CPU_ARC}/${rpm_ver}"
	rm -rf /etc/localtime
	ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

	sed -i 's/^exclude/#exclude/'  /etc/yum.conf && yum -y install gcc && sed -i 's/^#exclude/exclude/'  /etc/yum.conf

	##Downloading
	yum -y install git gcc gcc-c++ autoconf automake make
	yum -y install zlib zlib-devel openssl openssl--devel pcre pcre-devel
	yum -y install yum-fastestmirror
	yum -y install ntpdate ntp
	ntpdate -u pool.ntp.org
	/sbin/hwclock -w
}

#get_system_basic_info


cur_dir=`pwd`


## complie nginx with new args
groupadd www
useradd -g www -s /bin/false -M www

echo "===========================tengine install start===================================="
pushd tengine

./configure \
--prefix=/usr/local/nginx \
--lock-path=/var/lock/nginx.lock \
--pid-path=/var/run/nginx.pid \
--error-log-path=/var/logs/nginx/error.log \
--http-log-path=/var/logs/nginx/access.log \
--user=www --group=www \
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
make && make install;
popd
echo "===========================tengine install completed================================"

echo "===========================nginx module install start===================================="
/usr/local/nginx/sbin/dso_tool -a=$cur_dir/lua-nginx-module

echo "===========================nginx module install start===================================="

