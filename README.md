# [Scalr](https://scalr.com) POC

Goal:
- Store the state in one central, secure place: no more local `terraform.tfstate` or self-managed S3 bucket. Locking is built in, so two people cannot overwrite the state at the same time.
- Run `plan` and `apply` remotely, on Scalr's runners, instead of on a laptop.


## Gaps to fix

| Today | Expected with Scalr | Gap |
|---|---|---|
| The plan is only seen on the laptop that applies | The plan shows on every PR | Gap 1 |
| Apply is manual, with no approval and no trace | Apply on merge, approved and logged | Gap 14 |
| Any branch can be applied from any laptop | Only `main` is applied (to test) | Uncontrolled apply |
| Prod secrets live on laptops | Secrets live in Scalr | C3, C4 |
| State with plaintext secrets in a shared bucket | State in Scalr, access per workspace | C1 |
| Manual UI changes are only seen by a manual plan | Scheduled drift detection | C2 |

Today the state file is in an AWS S3 bucket. We want Scalr to manage it instead.

## Accounts

| Account | Plan | Used for |
|---|---|---|
| GitHub | personal, private repo | code, PRs, merges |
| Grafana Cloud | Free (IRM for up to 3 users) | the stack Terraform configures |
| Scalr | Free (50 runs/month) | state, plans, applies, drift detection |
| Slack | personal | Scalr notifications |

## Tools and versions

| Tool | Version | Why |
|---|---|---|
| Terraform | `1.15.8` | same as the prod CI |
| Provider `grafana/grafana` | `~> 3.18`, locked in `.terraform.lock.hcl` | same as prod |
| git / gh | `2.55.0` / `2.97.0` | already installed |


## Steps:

1- Install Terraform via `make setup`

2- Set up Grafana Cloud
    - Create a Grafana Cloud account (14-day trial, then Free tier).
    - Create a Stack:
        - URL: `https://olivebus357.grafana.net`
        - Region: Europe (Ireland)
    - Create the service account:
        - What: a "robot user" that Terraform uses to act on the stack. Terraform authenticates with a token of this service account.
        - **Administration → Users and access → Service accounts → Add service account**
        - Name: `terraform-scalr`
        - Role: `Admin` (needed to manage folders, alerts and permissions)
    - Grafana needs 2 tokens, with different jobs:
        - The service account token configures Grafana: folders, dashboards, alerts. Terraform uses it. It is the key to the admin office.
            - Token name: `terraform-scalr-token`
            - Expiration: `2027-04-07`
            - The token starts with `glsa_` and is shown only once.
        - The metrics token only sends data (metrics) to the stack. The GitHub workflow uses it. It is the slot of a mailbox: you can drop data in, nothing else.
            - Created from the grafana.com portal: stack `olivebus357` → **Details** → **InfluxDB Connectivity** → **Configure**
            - Token name: `github-actions-metrics-write`
            - Expiration: `2028-04-07`

3- Store the tokens in 1Password
    - Install the 1Password CLI and enable **Settings → Developer → Integrate with 1Password CLI**.
    - Create the `terraform-scalr-poc` vault.
    - Store `grafana-terraform-scalr-token` (API Credential): lets Terraform configure the stack.
    - Store `grafana-github-metrics-write-token` (API Credential): lets the GitHub workflow send metrics to Grafana.
    - Store `github-fg-token` (API Credential): lets terraform configure environment on github.


4- Configure Terraform
    - **Provider**: a plugin that lets Terraform create resources in a service. Here, `grafana/grafana`.
    - Files:
        - `.terraform-version`: pins the Terraform version (`1.15.8`).
        - `versions.tf`: pins the Grafana provider version (`~> 3.18`).
        - `providers.tf`: tells Terraform how to connect to the stack. The token is read from the `GRAFANA_AUTH` environment variable, never written in the file.
        - `dashboards.tf`: first resource, a "Scalr POC" folder.

## Target use-case

```
push → GitHub workflow → sends success=1 or 0 → Grafana Cloud metrics
                                                  ├→ dashboard: one point per push
                                                  └→ alert "failure" or "no data" → OnCall → me
```

### Add an alert on Grafana

- https://olivebus357.grafana.net/alerting
