# -----------------------------------------------------------------------------
# Data module - stateful tier, built for cross-regional resilience
#   Cloud SQL  : REGIONAL (HA, synchronous standby in 2nd zone) + PITR
#                + cross-region read replica (promotable for DR)
#   Memorystore: STANDARD_HA (replica in another zone, auto-failover)
#   Firestore  : multi-region database (synchronous replication across regions)
# All private IP only - nothing reachable from the internet.
# The caller must add `depends_on = [module.network]` so the Private Services
# Access peering exists before any private-IP instance is created.
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------- Cloud SQL
# Audit + troubleshooting flags (CIS PostgreSQL benchmark, checked by checkov)
resource "google_sql_database_instance" "primary" {
  project             = var.project_id
  name                = "pg-primary-${var.name_suffix}"
  region              = var.primary_region
  database_version    = var.sql_database_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.sql_tier
    edition           = "ENTERPRISE"
    availability_type = "REGIONAL" # HA: synchronous standby in another zone
    disk_type         = "PD_SSD"
    disk_size         = 20
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      location                       = var.secondary_region # backups stored OUTSIDE the primary region

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = false
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }
    database_flags {
      name  = "pgaudit.log"
      value = "ddl,role"
    }
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
    database_flags {
      name  = "log_hostname"
      value = "on"
    }
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
    database_flags {
      name  = "log_min_error_statement"
      value = "error"
    }
    database_flags {
      name  = "log_min_messages"
      value = "error"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = "500"
    }
  }
}

resource "google_sql_database_instance" "replica" {
  count = var.enable_sql_replica ? 1 : 0

  project              = var.project_id
  name                 = "pg-replica-${var.name_suffix}"
  region               = var.secondary_region
  database_version     = var.sql_database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = var.sql_tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    database_flags {
      name  = "cloudsql.enable_pgaudit"
      value = "on"
    }
    database_flags {
      name  = "pgaudit.log"
      value = "ddl,role"
    }
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }
    database_flags {
      name  = "log_hostname"
      value = "on"
    }
    database_flags {
      name  = "log_statement"
      value = "ddl"
    }
    database_flags {
      name  = "log_min_error_statement"
      value = "error"
    }
    database_flags {
      name  = "log_min_messages"
      value = "error"
    }
  }
}

resource "google_sql_database" "app" {
  for_each = toset(var.app_names)

  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = each.key
}

# IAM database auth: pods log in with their Workload Identity - no DB password in the app.
resource "google_sql_user" "app_iam" {
  for_each = var.app_service_accounts

  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = trimsuffix(each.value, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Break-glass admin user; password lives only in Secret Manager.
resource "random_password" "sql_admin" {
  length  = 32
  special = false
}

resource "google_sql_user" "admin" {
  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = "pgadmin"
  password = random_password.sql_admin.result
}

resource "google_secret_manager_secret" "sql_admin" {
  project   = var.project_id
  secret_id = "cloudsql-admin-password"

  replication {
    user_managed {
      dynamic "replicas" {
        for_each = var.secret_replica_regions
        content {
          location = replicas.value
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "sql_admin" {
  secret      = google_secret_manager_secret.sql_admin.id
  secret_data = random_password.sql_admin.result
}

# One-shot schema/grant job (Helm hook in charts/app): the only workload that may read the admin password.
resource "google_service_account" "db_init" {
  project      = var.project_id
  account_id   = "wl-db-init"
  display_name = "Database schema and grants job"
}

resource "google_project_iam_member" "db_init_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.db_init.email}"
}

resource "google_secret_manager_secret_iam_member" "db_init_admin_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.sql_admin.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.db_init.email}"
}

# ---------------------------------------------------------------- Memorystore Redis
resource "google_redis_instance" "cache" {
  project            = var.project_id
  name               = "cache-${var.name_suffix}"
  region             = var.primary_region
  tier               = "STANDARD_HA" # primary + replica in different zones, auto failover
  memory_size_gb     = var.redis_memory_gb
  redis_version      = "REDIS_7_2"
  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  read_replicas_mode = "READ_REPLICAS_DISABLED"

  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "TWELVE_HOURS"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours = 3
      }
    }
  }
}

# Connection secrets for the cache client; only the app named in redis_app can read them.
resource "google_secret_manager_secret" "redis" {
  for_each = toset(["redis-auth-string", "redis-ca-cert"])

  project   = var.project_id
  secret_id = each.key

  replication {
    user_managed {
      dynamic "replicas" {
        for_each = var.secret_replica_regions
        content {
          location = replicas.value
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "redis_auth" {
  secret      = google_secret_manager_secret.redis["redis-auth-string"].id
  secret_data = google_redis_instance.cache.auth_string
}

resource "google_secret_manager_secret_version" "redis_ca" {
  secret      = google_secret_manager_secret.redis["redis-ca-cert"].id
  secret_data = google_redis_instance.cache.server_ca_certs[0].cert
}

resource "google_secret_manager_secret_iam_member" "redis_client" {
  for_each = google_secret_manager_secret.redis

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_accounts[var.redis_app]}"
}

resource "google_storage_bucket" "redis_dr" {
  project                     = var.project_id
  name                        = "${var.project_id}-redis-dr"
  location                    = "US"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = 30
    }
  }
}

resource "google_storage_bucket_iam_member" "redis_persistence" {
  bucket = google_storage_bucket.redis_dr.name
  role   = "roles/storage.objectAdmin"
  member = google_redis_instance.cache.persistence_iam_identity
}

resource "google_storage_bucket_iam_member" "redis_persistence_bucket_viewer" {
  bucket = google_storage_bucket.redis_dr.name
  role   = "roles/storage.bucketViewer"
  member = google_redis_instance.cache.persistence_iam_identity
}

resource "google_service_account" "redis_backup" {
  project      = var.project_id
  account_id   = "redis-backup-${var.name_suffix}"
  display_name = "Redis scheduled RDB export"
}

resource "google_project_iam_custom_role" "redis_exporter" {
  project     = var.project_id
  role_id     = "redisRdbExporter"
  title       = "Memorystore Redis RDB exporter"
  description = "Allows scheduled Redis RDB exports; does not manage Redis instances."
  stage       = "GA"
  permissions = ["redis.instances.export"]
}

resource "google_project_iam_member" "redis_exporter" {
  project = var.project_id
  role    = google_project_iam_custom_role.redis_exporter.name
  member  = google_service_account.redis_backup.member
}

resource "google_project_iam_member" "redis_export_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = google_service_account.redis_backup.member
}

resource "google_cloud_scheduler_job" "redis_export" {
  project          = var.project_id
  region           = var.primary_region
  name             = "redis-rdb-export-${var.name_suffix}"
  description      = "Export the primary Redis cache to a versioned cross-region bucket every 12 hours."
  schedule         = "0 */12 * * *"
  time_zone        = "Etc/UTC"
  attempt_deadline = "1800s"

  retry_config {
    retry_count          = 3
    min_backoff_duration = "60s"
    max_backoff_duration = "3600s"
    max_doublings        = 3
  }

  http_target {
    http_method = "POST"
    uri         = "https://redis.googleapis.com/v1/projects/${var.project_id}/locations/${var.primary_region}/instances/${google_redis_instance.cache.name}:export"
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode({
      outputConfig = {
        gcsDestination = {
          uri = "gs://${google_storage_bucket.redis_dr.name}/latest/cache.rdb"
        }
      }
    }))

    oauth_token {
      service_account_email = google_service_account.redis_backup.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_iam_member.redis_exporter,
    google_project_iam_member.redis_export_service_usage,
    google_storage_bucket_iam_member.redis_persistence,
    google_storage_bucket_iam_member.redis_persistence_bucket_viewer,
  ]
}

resource "google_redis_instance" "cache_dr" {
  count = var.enable_redis_dr_instance ? 1 : 0

  project            = var.project_id
  name               = "cache-dr-${var.name_suffix}"
  region             = var.secondary_region
  tier               = "STANDARD_HA"
  memory_size_gb     = var.redis_memory_gb
  redis_version      = "REDIS_7_2"
  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  read_replicas_mode = "READ_REPLICAS_DISABLED"

  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "TWELVE_HOURS"
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours = 3
      }
    }
  }
}

# ---------------------------------------------------------------- Firestore
resource "google_firestore_database" "default" {
  project                           = var.project_id
  name                              = "(default)"
  location_id                       = var.firestore_location # multi-region: 99.999% SLA
  type                              = "FIRESTORE_NATIVE"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = var.deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = var.deletion_protection ? "ABANDON" : "DELETE"
}

resource "google_firestore_backup_schedule" "daily" {
  project  = var.project_id
  database = google_firestore_database.default.name

  retention = "604800s" # 7 days

  daily_recurrence {}
}
