# Name of the GitHub repository that holds the metrics workflow.
variable "github_repository" {
  type    = string
  default = "scalr-learning"
}

# Grafana Cloud URL where the workflow pushes its data point (Influx line protocol).
variable "grafana_metrics_write_url" {
  type = string
}

# Grafana Cloud metrics instance ID, used as the username of the push.
variable "grafana_metrics_instance_id" {
  type =string
}

# Token that can only write metrics: hidden in Terraform's output, but still stored in the state.
variable "grafana_metrics_write_token" {
  type      = string
  sensitive = true
}
