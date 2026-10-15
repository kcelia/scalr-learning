# GitHub token read from AWS Secrets Manager at each run: ephemeral, so it never lands in the state or the plan.
ephemeral "aws_secretsmanager_secret_version" "github" {
  secret_id = "github-fg-token"
}
