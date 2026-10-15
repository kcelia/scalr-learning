# Provider: Grafana
# Empty on purpose: it reads GRAFANA_URL and GRAFANA_AUTH from the environment, injected by op run.
provider "grafana" {}

# Provider: integrations/github
# It lets Terraform create things in GitHub: the environment, its variables and its secrets.
# It reads GITHUB_OWNER from the environment; its token comes from AWS Secrets Manager (secrets.tf).
provider "github" {
  token = ephemeral.aws_secretsmanager_secret_version.github.secret_string
}

# Provider: AWS
# Region only: Scalr injects the temporary credentials of the OIDC provider configuration aws-oidc-kcelia.
provider "aws" {
  region = "eu-west-3"
}
