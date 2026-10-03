-- Panel 3: Request latency percentiles (p50 / p95 / p99)
-- Option A (user-facing, includes network + LB): global LB request logs
-- Source: sink "bq-lb-logs" -> table requests. httpRequest.latency is seconds (FLOAT).
SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE)                                AS time,
  APPROX_QUANTILES(httpRequest.latency * 1000, 100)[OFFSET(50)]     AS p50_ms,
  APPROX_QUANTILES(httpRequest.latency * 1000, 100)[OFFSET(95)]     AS p95_ms,
  APPROX_QUANTILES(httpRequest.latency * 1000, 100)[OFFSET(99)]     AS p99_ms
FROM `PROJECT_ID.platform_logs.requests`
WHERE $__timeFilter(timestamp)
GROUP BY time
ORDER BY time;

-- Option B (server-side only, per app): structured access logs written by the apps
-- SELECT
--   TIMESTAMP_TRUNC(timestamp, MINUTE)                                     AS time,
--   resource.labels.namespace_name                                         AS app,
--   APPROX_QUANTILES(CAST(jsonPayload.latency_ms AS FLOAT64), 100)[OFFSET(50)] AS p50_ms,
--   APPROX_QUANTILES(CAST(jsonPayload.latency_ms AS FLOAT64), 100)[OFFSET(95)] AS p95_ms,
--   APPROX_QUANTILES(CAST(jsonPayload.latency_ms AS FLOAT64), 100)[OFFSET(99)] AS p99_ms
-- FROM `PROJECT_ID.platform_logs.stdout`
-- WHERE $__timeFilter(timestamp) AND jsonPayload.latency_ms IS NOT NULL
-- GROUP BY time, app ORDER BY time;
