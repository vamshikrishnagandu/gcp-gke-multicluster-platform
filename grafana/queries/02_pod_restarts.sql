-- Panel 2: Pod restart counts by namespace
-- Source: sink "bq-gke-cluster-logs" -> table events (Kubernetes events)
-- A container restart produces a "BackOff" / "Killing" / "Started" event; BackOff
-- ("Back-off restarting failed container") and OOMKilling are the real restart signals.
SELECT
  TIMESTAMP_TRUNC(timestamp, HOUR)                AS time,
  jsonPayload.involvedobject.namespace            AS namespace,
  COUNT(*)                                        AS restarts
FROM `PROJECT_ID.platform_logs.events`
WHERE $__timeFilter(timestamp)
  AND jsonPayload.reason IN ('BackOff', 'OOMKilling', 'Unhealthy', 'Killing')
  AND jsonPayload.involvedobject.kind = 'Pod'
GROUP BY time, namespace
ORDER BY time
