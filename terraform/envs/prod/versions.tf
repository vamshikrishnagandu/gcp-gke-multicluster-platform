terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0" # 3.7+ needs macOS 12+ (M13)
    }
  }

  # Bucket name is supplied at init time so the code is not tied to one project:
  #   terraform init -backend-config="bucket=<project_id>-tfstate"
  backend "gcs" {
    prefix = "envs/prod"
  }
}
