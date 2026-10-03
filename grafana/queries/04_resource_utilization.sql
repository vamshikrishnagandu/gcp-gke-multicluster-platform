-- Panel 4: Resource utilisation trends (CPU / memory) per app and cluster
-- Source: GKE usage metering (dataset gke_usage, table gke_cluster_resource_consumption),
-- enabled by resource_usage_export_config on each cluster.
-- usage.amount units: cpu = core-seconds, memory = byte-seconds -> divide by the window length.
SELECT
  TIMESTAMP_TRUNC(start_time, HOUR)                                       AS time,
  CONCAT(namespace, ' / ', cluster_name)                                  AS series,
  SUM(IF(resource_name = 'cpu',
         usage.amount / TIMESTAMP_DIFF(end_time, start_time, SECOND), 0))  AS cpu_cores,
  SUM(IF(resource_name = 'memory',
         usage.amount / TIMESTAMP_DIFF(end_time, start_time, SECOND), 0)) / POW(1024, 3) AS memory_gib
FROM `PROJECT_ID.gke_usage.gke_cluster_resource_consumption`
WHERE $__timeFilter(start_time)
  AND namespace IN ('app1', 'app2')
GROUP BY time, series
ORDER BY time;

-- Near-real-time alternative (1-minute resolution): Grafana "Google Cloud Monitoring"
-- data source, PromQL:
--   sum by (namespace_name, cluster_name) (
--     rate(kubernetes_io:container_cpu_core_usage_time{monitored_resource="k8s_container", namespace_name=~"app1|app2"}[5m]))
--   sum by (namespace_name, cluster_name) (
--     kubernetes_io:container_memory_used_bytes{monitored_resource="k8s_container", namespace_name=~"app1|app2", memory_type="non-evictable"})

-- Bonus: HPA scale events per app (from Kubernetes events in platform_logs)
-- SELECT TIMESTAMP_TRUNC(timestamp, HOUR) AS time, jsonPayload.involvedobject.namespace AS app, COUNT(*) AS scale_events
-- FROM `PROJECT_ID.platform_logs.events`
-- WHERE $__timeFilter(timestamp) AND jsonPayload.reason = 'SuccessfulRescale'
-- GROUP BY time, app ORDER BY time;
