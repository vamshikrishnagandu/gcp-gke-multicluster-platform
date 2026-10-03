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

output "redis_host" {
  value = google_redis_instance.cache.host
}

output "redis_port" {
  value = google_redis_instance.cache.port
}

output "firestore_database" {
  value = google_firestore_database.default.name
}
