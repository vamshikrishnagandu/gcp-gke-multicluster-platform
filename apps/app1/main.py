"""app1 - "catalog" service.

Public routes are served under /app1 (the global Gateway routes by path prefix).
Uses Firestore (multi-region) for hit counts and Cloud SQL (PostgreSQL, IAM auth) for the item catalog,
both via Workload Identity - no keys, no passwords.
"""

import os
import random
import socket
import time

from flask import Blueprint, Flask, jsonify

from common import db, observability

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


def load_items():
    """Catalog from Cloud SQL; falls back to a static list so a database outage does not take /items down."""
    if db.enabled():
        try:
            conn = db.connect(os.environ["DB_USER"])
            try:
                cur = conn.cursor()
                cur.execute("SELECT id, name FROM catalog.items ORDER BY id")
                return [{"id": r[0], "name": r[1]} for r in cur.fetchall()], "cloudsql"
            finally:
                conn.close()
        except Exception:
            log.exception("Cloud SQL read failed; serving fallback items")
    return [{"id": i, "name": f"item-{i}"} for i in range(1, 6)], "fallback"


@bp.get("/items")
def items():
    """Hit counter in Firestore + catalog in Cloud SQL - demonstrates the data tier + traced downstream calls."""
    payload = where_am_i()
    db_client = firestore_client()
    if db_client is not None:
        ref = db_client.collection("stats").document(SERVICE)
        from google.cloud import firestore

        ref.set({"hits": firestore.Increment(1)}, merge=True)
        payload["hits"] = (ref.get().to_dict() or {}).get("hits")
    payload["items"], payload["items_source"] = load_items()
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
