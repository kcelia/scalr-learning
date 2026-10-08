# Provider: Grafana
# Empty on purpose: it reads GRAFANA_URL and GRAFANA_AUTH from the environment, injected by op run.
provider "grafana" {}

# Provider: integrations/github
# It lets Terraform create things in GitHub: the environment, its variables and its secret.
# Empty on purpose: it reads GITHUB_OWNER and GITHUB_TOKEN from the environment, injected by op run.
provider "github" {}
