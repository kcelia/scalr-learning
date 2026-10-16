# Reference: accounts, tools, files and commands

Back to the [README](README.md).

## Accounts

| Account | Plan | Used for |
|---|---|---|
| GitHub | personal, **public** repo: GitHub Free offers environments on public repos only | code, workflow, environment |
| Grafana Cloud | Free, IRM for up to 3 users | stack `olivebus357`, EU (Ireland) |
| Scalr | Free, 50 runs/month | state and runs |
| AWS | pay-as-you-go, region `eu-west-3` | Secrets Manager, SSM Parameter Store, IAM (scenario 2.2) |
| 1Password | vault `terraform-scalr-poc` | every token |

## Tools

| Tool | Version | Why |
|---|---|---|
| OpenTofu | `1.13.1`, in `.opentofu-version` | Scalr runs Terraform only up to 1.5.x |
| Terraform | `1.15.8`, in `.terraform-version` | the CI (`push-metrics`), until it moves to OpenTofu |
| tenv | `4.15.1` | installs the pinned version and checks its signature |
| `grafana/grafana` | `~> 3.18`, locked at `3.25.9` | Grafana resources |
| `integrations/github` | `~> 6.13`, locked at `6.13.0` | GitHub environment, variables, secrets |
| `hashicorp/aws` | `~> 6.69`, locked at `6.69.0` | Secrets Manager reads and the SSM parameter (scenario 2.2) |
| 1Password CLI | `2.40.0` | `op run` injects secrets at run time, never on disk |

## Files

| File | Content |
|---|---|
| `versions.tf` | OpenTofu (`>= 1.11`) and provider versions, Scalr `backend "remote"` |
| `providers.tf` | `grafana`: credentials from the environment (Scalr shell variables); `github`: token from Secrets Manager (`ephemeral`); `aws`: region only, credentials from Scalr OIDC |
| `secrets.tf` | Secrets Manager reads (`ephemeral` and `data`) and the write-only SSM test (`aws_ssm_parameter.value_wo`) |
| `variables.tf` | inputs; secrets are `sensitive`; `poc_fake_secret` is also `ephemeral` (test) |
| `datasources.tf` | the stack's Prometheus data source, read and not created |
| `dashboards.tf` | folder "Scalr POC" and dashboard "GitHub push results (scalr - VCS)" |
| `alerts.tf` | email contact point and alert "main is broken" |
| `github.tf` | environment `env-poc-grafana-metrics` (main only), 2 variables, 1 secret (`POC_FAKE_SECRET` is commented out) |
| `.github/workflows/push-metrics.yml` | checks on every push; on `main`, sends the result to Grafana |
| `scripts/push_vars_to_scalr.py` | copies the variables from 1Password to the Scalr workspace |
| `.env.example` | template of `secrets.env.op` (git-ignored): 1Password references only |
| `.terraformignore` | allowlist of what `tofu` uploads to Scalr: the `.tf` files and `.terraform.lock.hcl` |
| `AWS-SETUP.md` | AWS setup for scenario 2.2: secrets, OIDC identity provider, IAM role |

## Commands

| Command | What it does |
|---|---|
| `make help` | list the commands |
| `make setup` | install tenv, OpenTofu and the 1Password CLI |
| `make init` | download the providers and connect to the Scalr backend |
| `make plan` | run a plan of the **local** code on Scalr (allowed in both modes) |
| `make apply` | CLI-driven only: refused once the workspace is VCS-driven |
| `make migrate-state` | one time only: copy a local state to Scalr |
| `make push-vars-to-scalr` | copy the 8 variables (3 sensitive) to the Scalr workspace |
| `make check-token-{grafana,oncall,github,scalr}` | check one token from 1Password |
| `make push-metric` | send one test point to Grafana |
