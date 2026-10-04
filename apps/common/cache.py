"""Memorystore Redis client (TLS + AUTH). Returns None when Redis is not configured or unreachable."""

import logging
import os

from common.secrets import read_secret

log = logging.getLogger("cache")
_client = None


def client():
    global _client
    host = os.getenv("REDIS_HOST")
    if not host:
        return None
    if _client is None:
        try:
            import redis

            _client = redis.Redis(
                host=host,
                port=int(os.getenv("REDIS_PORT", "6378")),
                password=read_secret(os.environ["REDIS_AUTH_SECRET"]),
                ssl=True,
                ssl_cert_reqs="required",
                ssl_ca_data=read_secret(os.environ["REDIS_CA_SECRET"]),
                ssl_check_hostname=False,  # server cert is issued to the instance, not to its IP
                socket_connect_timeout=1,
                socket_timeout=1,
            )
        except Exception:
            log.exception("Redis client setup failed")
            return None
    return _client
