import redis
import json

r = redis.Redis("127.0.0.1",6379)
settings = dict(gzip="on", server_type=0, upstream="server 121.43.108.134:80;")
pub_msg = dict(hostname="www.visionad.com.cn",sett=settings)
r.publish("ngx.ConfigEvent",json.dumps(pub_msg) )
