"""app2 - "orders" service.

Calls app1 through the Multi-Cluster Service DNS name
(app1.app1.svc.clusterset.local) so a request can hop regions -> visible as
two spans in Cloud Trace. Reads its API key from Secret Manager at startup.
"""

import os
import socket

import requests
from flask import Blueprint, Flask, jsonify

from common import observability

SERVICE = "app2"
APP1_URL = os.getenv("APP1_URL", "http://app1.app1.svc.clusterset.local:8080/app1/items")

app = Flask(__name__)
log = observability.init(app)
bp = Blueprint(SERVICE, __name__, url_prefix=f"/{SERVICE}")


def load_api_key() -> str:
    """Secret Manager via Workload Identity. The key is never in the image, manifest or env."""
    name = os.getenv("API_KEY_SECRET", "")
    if not name:
        return ""
    try:
        from google.cloud import secretmanager

        client = secretmanager.SecretManagerServiceClient()
        return client.access_secret_version(name=name).payload.data.decode()
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
    try:
        resp = requests.get(APP1_URL, timeout=2)
        resp.raise_for_status()
        payload["catalog"] = resp.json()
    except requests.RequestException as exc:
        log.error("app1 call failed: %s", exc)
        payload["catalog"] = None
        return jsonify(payload), 502
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
