#!/usr/bin/env python

import redis
import json
import sys

if len(sys.argv) < 2:
    print "usage %s reload|flush" %(sys.argv[0])
    sys.exit()

cmd = sys.argv[1]
pub_msg = ""

REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379

redis = redis.Redis(REDIS_HOST, REDIS_PORT)

if cmd == "load":
	pub_msg = dict(event="load_config")

elif cmd == "reload":
	pub_msg = dict(event="reload_config")

elif cmd == "flush":
	pub_msg = dict(event="flush_config")

elif cmd == "remove":
	pub_msg = dict(event="remove_config", hostname="www.100.com")

elif cmd == "loadtest":
	count = 1
	while count <= 10000:
		settings = dict(gzip="on", server_type=0, upstream="server 127.0.0.1:81;")
		pub_msg = dict(event="add_config", hostname="www." + str(count) + ".com",sett=settings)
		redis.publish("cdn.event", json.dumps(pub_msg) )
		count += 1
	sys.exit()

elif cmd == "test2redis":
	count = 1
	while count <= 100000:
		settings = dict(gzip="on", server_type=0, upstream="server 127.0.0.1:8088;")
		redis.set("site_" + "www." + str(count) + ".com", json.dumps(settings) )
		count += 1
	sys.exit()
			
if pub_msg == "":
	print "error cmd: %s" %(cmd)
else:
	print "push to cdn.event: %s" %(json.dumps(pub_msg))
	redis.publish("cdn.event", json.dumps(pub_msg) )

