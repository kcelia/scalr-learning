# Prometheus data source that Grafana Cloud created for the stack: Terraform reads it, it does not create it.
# Shared by the dashboard (dashboards.tf) and the alert (alerts.tf).
data "grafana_data_source" "metrics" {
  uid = "grafanacloud-prom"
}
