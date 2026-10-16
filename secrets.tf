# GitHub token read from AWS Secrets Manager at each run: ephemeral, so it never lands in the state or the plan.
ephemeral "aws_secretsmanager_secret_version" "github" {
  secret_id = "github-fg-token"
}

# TEMPORARY test: unlike the ephemeral read above, a data source stores the secret in clear in the state.
data "aws_secretsmanager_secret_version" "poc_fake" {
  secret_id = "poc-fake-secret"
}

# TEMPORARY test: the same secret read as ephemeral, so it can feed only a write-only attribute.
ephemeral "aws_secretsmanager_secret_version" "poc_fake" {
  secret_id = "poc-fake-secret"
}

# TEMPORARY test: SSM receives the value through value_wo, never stored in the state; bump value_wo_version to send a new one.
resource "aws_ssm_parameter" "poc_fake" {
  name             = "/scalr-poc/poc-fake-secret"
  type             = "SecureString"
  value_wo         = ephemeral.aws_secretsmanager_secret_version.poc_fake.secret_string
  value_wo_version = 1
}
