# Folder that holds the POC dashboards, like the one in prod.
resource "grafana_folder" "poc" {
  title = "Scalr POC"
}

# Dashboard that shows the result of each push to main over time (1 = success, 0 = failure).
resource "grafana_dashboard" "push_results" {
  folder = grafana_folder.poc.uid
  config_json = jsonencode({
    title = "GitHub push results"
    time  = { from = "now-24h", to = "now" }
    panels = [{
      type       = "timeseries"
      title      = "Checks on main (1 = success, 0 = failure)"
      gridPos    = { x = 0, y = 0, w = 24, h = 9 }
      datasource = { type = "prometheus", uid = data.grafana_data_source.metrics.uid }
      targets = [{
        refId      = "A"
        datasource = { type = "prometheus", uid = data.grafana_data_source.metrics.uid }
        expr       = "github_push_success{repo=\"scalr-learning\", branch=\"main\"}"
      }]
      fieldConfig = {
        defaults = {
          min    = 0
          max    = 1
          custom = { drawStyle = "points", pointSize = 10 }
        }
        overrides = []
      }
    }]
  })
}
