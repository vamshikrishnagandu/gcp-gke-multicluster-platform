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
locals {
  pg_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "ddl,role"
    log_checkpoints               = "on"
    log_connections               = "on"
    log_disconnections            = "on"
    log_lock_waits                = "on"
    log_hostname                  = "on"
    log_statement                 = "ddl"
    log_min_error_statement       = "error"
    log_min_messages              = "error"
  }
}

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

    dynamic "database_flags" {
      for_each = merge(local.pg_flags, { log_min_duration_statement = "500" }) # slow queries > 500 ms
      content {
        name  = database_flags.key
        value = database_flags.value
      }
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

    dynamic "database_flags" {
      for_each = local.pg_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
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
  replica_count      = 1
  read_replicas_mode = "READ_REPLICAS_ENABLED"

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
