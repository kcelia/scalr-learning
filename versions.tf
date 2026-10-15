# OpenTofu 1.11 or later for ephemeral resources (Scalr does not run Terraform above 1.5), Grafana provider 3.x from 3.18 as in prod.
terraform {
  required_version = ">= 1.11"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.18"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Scalr stores the state (CLI-driven workspace, created by the first init).
  # Backend blocks cannot use variables, so the account and environment ID are written here.
  backend "remote" {
    hostname     = "kcelia.scalr.io"
    organization = "env-v0pejs6i46opjvptq"

    workspaces {
      name = "scalr-learning"
    }
  }
}
