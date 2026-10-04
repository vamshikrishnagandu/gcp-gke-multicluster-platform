output "sql_connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "sql_private_ip" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "sql_replica_connection_name" {
  value = try(google_sql_database_instance.replica[0].connection_name, null)
}

output "sql_iam_users" {
  value = { for k, u in google_sql_user.app_iam : k => u.name }
}

output "db_init_service_account" {
  value = google_service_account.db_init.email
}

output "db_init_service_account_name" {
  value = google_service_account.db_init.name
}

output "redis_host" {
  value = google_redis_instance.cache.host
}

output "redis_port" {
  value = google_redis_instance.cache.port
}

output "redis_dr_backup_bucket" {
  value = google_storage_bucket.redis_dr.name
}

output "redis_dr_host" {
  value = try(google_redis_instance.cache_dr[0].host, null)
}

output "firestore_database" {
  value = google_firestore_database.default.name
}
