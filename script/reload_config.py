import redis
import json

r = redis.Redis("127.0.0.1",6379)
pub_msg = dict(event="reload_config")
r.publish("cdn.event",json.dumps(pub_msg) )
