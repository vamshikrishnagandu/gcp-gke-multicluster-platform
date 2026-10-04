-- Panel 1: Application error rate over time (per app, per cluster)
-- Source: sink "bq-app-logs" -> tables stdout / stderr (one table per log name)
-- Grafana: Time series, macro $__timeFilter() limits the partition scan (cost!)
SELECT
  TIMESTAMP_TRUNC(timestamp, MINUTE)                         AS time,
  resource.labels.namespace_name                             AS app,
  resource.labels.cluster_name                               AS cluster,
  COUNTIF(severity IN ('ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')) AS errors,
  COUNT(*)                                                   AS total,
  SAFE_DIVIDE(COUNTIF(severity IN ('ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')), COUNT(*)) * 100 AS error_rate_pct
FROM `PROJECT_ID.platform_logs.stdout`
WHERE $__timeFilter(timestamp)
  AND resource.labels.namespace_name IN ('app1', 'app2')
  AND httpRequest.status IS NOT NULL   -- access-log lines only
GROUP BY time, app, cluster
ORDER BY time
