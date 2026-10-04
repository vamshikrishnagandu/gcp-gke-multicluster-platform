"""app2 - "orders" service.

Calls app1 through the Multi-Cluster Service DNS name
(app1.app1.svc.clusterset.local) so a request can hop regions -> visible as
two spans in Cloud Trace. Reads its API key from Secret Manager at startup and
caches the app1 catalog in Memorystore Redis (30 s TTL, TLS + AUTH).
"""

import json
import os
import socket

import requests
from flask import Blueprint, Flask, jsonify

from common import cache, observability
from common.secrets import read_secret

SERVICE = "app2"
APP1_URL = os.getenv("APP1_URL", "http://app1.app1.svc.clusterset.local:8080/app1/items")
CACHE_KEY = "catalog:items"
CACHE_TTL_SECONDS = 30

app = Flask(__name__)
log = observability.init(app)
bp = Blueprint(SERVICE, __name__, url_prefix=f"/{SERVICE}")


def load_api_key() -> str:
    """Secret Manager via Workload Identity. The key is never in the image, manifest or env."""
    name = os.getenv("API_KEY_SECRET", "")
    if not name:
        return ""
    try:
        return read_secret(name)
    except Exception:
        log.exception("Could not read secret %s", name)
        return ""


API_KEY = load_api_key()


def where_am_i():
    return {
        "service": SERVICE,
        "version": observability.VERSION,
        "pod": socket.gethostname(),
        "cluster": observability.CLUSTER,
        "region": observability.REGION,
        "api_key_loaded": bool(API_KEY),  # never log the value itself
    }


@bp.get("/")
def index():
    return jsonify(where_am_i())


@bp.get("/healthz")
def healthz():
    return {"status": "ok"}


@bp.get("/orders")
def orders():
    payload = where_am_i()
    redis_client = cache.client()
    payload["cache"] = "disabled" if redis_client is None else "miss"
    if redis_client is not None:
        try:
            cached = redis_client.get(CACHE_KEY)
            if cached:
                payload["catalog"] = json.loads(cached)
                payload["cache"] = "hit"
                return jsonify(payload)
        except Exception:
            log.exception("Redis read failed; calling app1")
            payload["cache"] = "unavailable"
            redis_client = None
    try:
        resp = requests.get(APP1_URL, timeout=2)
        resp.raise_for_status()
        payload["catalog"] = resp.json()
    except requests.RequestException as exc:
        log.error("app1 call failed: %s", exc)
        payload["catalog"] = None
        return jsonify(payload), 502
    if redis_client is not None:
        try:
            redis_client.setex(CACHE_KEY, CACHE_TTL_SECONDS, json.dumps(payload["catalog"]))
        except Exception:
            log.exception("Redis write failed")
    return jsonify(payload)


@bp.get("/error")
def error():
    raise ValueError("Simulated failure in app2 (/app2/error)")


app.register_blueprint(bp)


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
