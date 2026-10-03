"""app1 - "catalog" service.

Public routes are served under /app1 (the global Gateway routes by path prefix).
Uses Firestore (multi-region) via Workload Identity - no keys, no passwords.
"""

import os
import random
import socket
import time

from flask import Blueprint, Flask, jsonify

from common import observability

SERVICE = "app1"
app = Flask(__name__)
log = observability.init(app)
bp = Blueprint(SERVICE, __name__, url_prefix=f"/{SERVICE}")

_db = None


def firestore_client():
    global _db
    if _db is None and os.getenv("ENABLE_FIRESTORE", "true") == "true":
        from google.cloud import firestore

        _db = firestore.Client()
    return _db


def where_am_i():
    return {
        "service": SERVICE,
        "version": observability.VERSION,
        "pod": socket.gethostname(),
        "cluster": observability.CLUSTER,
        "region": observability.REGION,
    }


@bp.get("/")
def index():
    return jsonify(where_am_i())


@bp.get("/healthz")
def healthz():
    return {"status": "ok"}


@bp.get("/items")
def items():
    """Reads a counter from Firestore - demonstrates the data tier + a traced downstream call."""
    payload = where_am_i()
    db = firestore_client()
    if db is not None:
        ref = db.collection("stats").document(SERVICE)
        from google.cloud import firestore

        ref.set({"hits": firestore.Increment(1)}, merge=True)
        payload["hits"] = (ref.get().to_dict() or {}).get("hits")
    payload["items"] = [{"id": i, "name": f"item-{i}"} for i in range(1, 6)]
    return jsonify(payload)


@bp.get("/work")
def work():
    """CPU-bound endpoint: drives HPA scaling and shows up in Cloud Profiler flame graphs."""
    n = 0
    end = time.perf_counter() + random.uniform(0.05, 0.2)
    while time.perf_counter() < end:
        n += 1
    return {"iterations": n, **where_am_i()}


@bp.get("/error")
def error():
    """Deliberate exception -> appears grouped in Error Reporting."""
    raise RuntimeError("Simulated failure in app1 (/app1/error)")


app.register_blueprint(bp)


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
