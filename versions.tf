# Same constraints as prod: Terraform 1.10 or later, Grafana provider 3.x from 3.18.
terraform {
  required_version = ">= 1.10"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.18"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}
