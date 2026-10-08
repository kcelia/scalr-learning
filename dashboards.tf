# Folder that holds the POC dashboards, like the one in prod.
resource "grafana_folder" "poc" {
  title = "Scalr POC"
}
