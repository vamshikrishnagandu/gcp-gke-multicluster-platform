"""Shared observability bootstrap for both apps.

Wires every signal the platform promises:
  logs     -> JSON on stdout. GKE's logging agent ships it to Cloud Logging;
              `severity`, `httpRequest` and `logging.googleapis.com/trace` are
              special fields Cloud Logging understands (and the BigQuery sink keeps).
  traces   -> OpenTelemetry -> Cloud Trace (W3C traceparent propagated to downstream calls)
  profiles -> Cloud Profiler agent (CPU + heap, ~1% overhead)
  errors   -> ERROR logs containing a stack trace are grouped by Error Reporting
              automatically - no extra client needed.
  metrics  -> Prometheus /metrics, scraped by Google Managed Prometheus (PodMonitoring)
"""

import json
import logging
import os
import sys
import time
import traceback

from flask import Flask, Response, g, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


def _metadata(path: str, default: str) -> str:
    """Ask the GKE metadata server (only reachable inside GKE). Same image runs
    in every cluster and discovers WHERE it is at runtime - no per-cluster config."""
    try:
        import urllib.request

        req = urllib.request.Request(
            f"http://metadata.google.internal/computeMetadata/v1/{path}",
            headers={"Metadata-Flavor": "Google"},
        )
        with urllib.request.urlopen(req, timeout=1) as resp:
            return resp.read().decode()
    except OSError:  # URLError/timeouts: not on GCE/GKE (laptop, CI)
        return default


PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT") or _metadata("project/project-id", "")
SERVICE = os.getenv("SERVICE_NAME", "app")
VERSION = os.getenv("SERVICE_VERSION", "dev")
CLUSTER = os.getenv("CLUSTER_NAME") or _metadata("instance/attributes/cluster-name", "local")
REGION = os.getenv("CLUSTER_REGION") or _metadata("instance/attributes/cluster-location", "local")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["service", "route", "method", "code"])
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["service", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "serviceContext": {"service": SERVICE, "version": VERSION},
            "cluster": CLUSTER,
            "region": REGION,
        }
        if record.exc_info:
            # A stack trace inside `message` is what Error Reporting detects.
            entry["message"] += "\n" + "".join(traceback.format_exception(*record.exc_info))
            entry["@type"] = "type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent"
        for key in ("httpRequest", "logging.googleapis.com/trace", "logging.googleapis.com/spanId", "latency_ms"):
            if hasattr(record, key.replace(".", "_").replace("/", "_")):
                entry[key] = getattr(record, key.replace(".", "_").replace("/", "_"))
        return json.dumps(entry)


def _setup_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)
    return logging.getLogger(SERVICE)


def _setup_tracing(app: Flask) -> None:
    if os.getenv("ENABLE_TRACING", "true") != "true" or not PROJECT_ID:
        return
    from opentelemetry import trace
    from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
    from opentelemetry.instrumentation.flask import FlaskInstrumentor
    from opentelemetry.instrumentation.requests import RequestsInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.sdk.trace.sampling import ParentBasedTraceIdRatio

    ratio = float(os.getenv("TRACE_SAMPLE_RATIO", "0.2"))
    provider = TracerProvider(
        resource=Resource.create({"service.name": SERVICE, "service.version": VERSION, "k8s.cluster.name": CLUSTER}),
        sampler=ParentBasedTraceIdRatio(ratio),
    )
    provider.add_span_processor(BatchSpanProcessor(CloudTraceSpanExporter(project_id=PROJECT_ID)))
    trace.set_tracer_provider(provider)
    FlaskInstrumentor().instrument_app(app, excluded_urls="healthz,readyz,metrics")
    RequestsInstrumentor().instrument()


def _setup_profiler(log: logging.Logger) -> None:
    if os.getenv("ENABLE_PROFILER", "true") != "true" or not PROJECT_ID:
        return
    try:
        import googlecloudprofiler

        googlecloudprofiler.start(service=SERVICE, service_version=VERSION, verbose=0)
    except Exception:  # noqa: BLE001 - profiler must never take the app down
        log.warning("Cloud Profiler not started", exc_info=False)


def _current_trace_ids():
    try:
        from opentelemetry import trace

        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            return f"projects/{PROJECT_ID}/traces/{ctx.trace_id:032x}", f"{ctx.span_id:016x}"
    except ImportError:  # tracing libs absent -> log without trace correlation
        return None, None
    return None, None


def init(app: Flask) -> logging.Logger:
    log = _setup_logging()
    _setup_tracing(app)
    _setup_profiler(log)

    @app.before_request
    def _start():
        g.start = time.perf_counter()

    @app.after_request
    def _access_log(resp: Response):
        route = request.url_rule.rule if request.url_rule else "unmatched"
        if route in ("/healthz", "/readyz", "/metrics"):
            return resp
        elapsed = time.perf_counter() - g.get("start", time.perf_counter())
        REQUESTS.labels(SERVICE, route, request.method, str(resp.status_code)).inc()
        LATENCY.labels(SERVICE, route).observe(elapsed)
        trace_id, span_id = _current_trace_ids()
        extra = {
            "httpRequest": {
                "requestMethod": request.method,
                "requestUrl": request.path,
                "status": resp.status_code,
                "userAgent": request.headers.get("User-Agent", ""),
                "remoteIp": request.headers.get("X-Forwarded-For", request.remote_addr),
                "latency": f"{elapsed:.6f}s",
            },
            "latency_ms": round(elapsed * 1000, 3),
        }
        if trace_id:
            extra["logging_googleapis_com_trace"] = trace_id
            extra["logging_googleapis_com_spanId"] = span_id
        level = logging.ERROR if resp.status_code >= 500 else logging.INFO
        log.log(level, f"{request.method} {request.path} {resp.status_code}", extra=extra)
        return resp

    @app.errorhandler(Exception)
    def _unhandled(exc):
        from werkzeug.exceptions import HTTPException

        if isinstance(exc, HTTPException):  # 404/405 etc. are not server errors
            return exc
        log.exception("Unhandled exception on %s", request.path)
        return {"error": "internal error"}, 500

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return log
