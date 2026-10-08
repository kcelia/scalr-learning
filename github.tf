# -----------------------------------------------------------------------------
# GitHub environment for the Grafana metrics
#
# Terraform configures the GitHub repository here, instead of clicking in
# Settings > Environments. It creates one environment that holds the 3 values
# the workflow needs to push a data point to Grafana Cloud:
#   - the write URL      (variable, not secret)
#   - the instance ID    (variable, not secret)
#   - the write token    (secret)
#
# The values come from Terraform variables (variables.tf), filled by the
# TF_VAR_* environment variables that `op run` reads from 1Password.
# -----------------------------------------------------------------------------

# Environment that holds the metrics settings.
# Only workflow jobs that declare `environment: grafana-metrics` can read its
# variables and secrets.
resource "github_repository_environment" "grafana_metrics" {
  repository  = var.github_repository
  environment = "env-poc-grafana-metrics"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# Only the main branch may use the environment.
resource "github_repository_environment_deployment_policy" "main_only" {
  repository     = var.github_repository
  environment    = github_repository_environment.grafana_metrics.environment
  branch_pattern = "main"
}

# Where the workflow pushes its data point (not a secret).
resource "github_actions_environment_variable" "metrics_write_url" {
  repository    = var.github_repository
  environment   = github_repository_environment.grafana_metrics.environment
  variable_name = "GRAFANA_METRICS_WRITE_URL"
  value         = var.grafana_metrics_write_url
}

# Username of the push (not a secret).
resource "github_actions_environment_variable" "metrics_instance_id" {
  repository    = var.github_repository
  environment   = github_repository_environment.grafana_metrics.environment
  variable_name = "GRAFANA_METRICS_INSTANCE_ID"
  value         = var.grafana_metrics_instance_id
}

# Write-only token, stored as an environment secret; its value also lands in the Terraform state.
resource "github_actions_environment_secret" "metrics_write_token" {
  repository  = var.github_repository
  environment = github_repository_environment.grafana_metrics.environment
  secret_name = "GRAFANA_METRICS_WRITE_TOKEN"
  value       = var.grafana_metrics_write_token
}
