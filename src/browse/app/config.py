import os

TABLE_NAME = os.environ["TABLE_NAME"]
REDIS_HOST = os.environ["REDIS_HOST"]
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
AWS_REGION = os.environ["AWS_REGION"]
CACHE_TTL  = int(os.environ.get("CACHE_TTL", "300"))
