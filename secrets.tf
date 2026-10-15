# GitHub token read from AWS Secrets Manager at each run: ephemeral, so it never lands in the state or the plan.
ephemeral "aws_secretsmanager_secret_version" "github" {
  secret_id = "github-fg-token"
}

# TEMPORARY test: unlike the ephemeral read above, a data source stores the secret in clear in the state.
data "aws_secretsmanager_secret_version" "poc_fake" {
  secret_id = "poc-fake-secret"
}
