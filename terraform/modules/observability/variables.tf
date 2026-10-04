variable "project_id" {
  type = string
}

variable "bq_location" {
  description = "BigQuery dataset location (US multi-region)."
  type        = string
  default     = "US"
}

variable "log_retention_days" {
  description = "BigQuery table partition expiration."
  type        = number
  default     = 30
}

variable "uptime_host" {
  description = "Public hostname/IP of the global Gateway. Empty = skip uptime checks (first apply, before the LB exists)."
  type        = string
  default     = ""
}

variable "uptime_use_ssl" {
  description = "Probe https:443 and validate the certificate (true) or plain http:80 (false)."
  type        = bool
  default     = true
}

variable "uptime_paths" {
  description = "Paths probed by uptime checks (one per app)."
  type        = map(string)
  default = {
    app1 = "/app1/healthz"
    app2 = "/app2/healthz"
  }
}

variable "alert_email" {
  description = "E-mail for alert notifications. Empty = alerts without notification channel."
  type        = string
  default     = ""
}

variable "grafana_principal" {
  description = "Optional extra principal (e.g. user:you@gmail.com) granted BigQuery read for Grafana."
  type        = string
  default     = ""
}
