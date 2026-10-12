# Scalr POC

Test whether [Scalr](https://scalr.com) can run Terraform for a team instead of engineers' laptops.
Personal accounts and fake data only.

## Problems to fix

| Problem with laptop applies | Expected with Scalr | POC status |
|---|---|---|
| The plan is only seen on the laptop that applies | The plan shows on every PR | ⏳ VCS-driven |
| Applies have no approval and no trace | Applies are approved and logged | ✅ trace · ⏳ approval |
| Any branch can be applied from any laptop | Only `main` is applied | ⏳ VCS-driven |
| Secrets live on laptops | Runs get secrets from the platform | ✅ |
| The state, with secrets inside, sits in a self-managed bucket | State in Scalr, encrypted at rest, read access by permission | ✅ partly |
| Manual UI changes are only found by a manual plan | Scheduled drift detection | ⏳ |

## Phases

| Phase | Where plan and apply run | Status |
|---|---|---|
| A. Without Scalr | laptop, local state, secrets from 1Password (`op run`) | ✅ |
| B1. Scalr, CLI-driven | Scalr runners, started from the laptop | ✅ |
| B2. Scalr, VCS-driven | Scalr runners, started by PRs and merges | ⏳ |

## Use case

```
push ──▶ workflow push-metrics: fmt + init -backend=false + validate
           └─ on main only ──▶ success=1 or 0 ──▶ Grafana Cloud metrics
                                                    ├─▶ dashboard "GitHub push results (scalr)"
                                                    └─▶ alert "main is broken" ──▶ email
```

## Accounts

| Account | Plan | Used for |
|---|---|---|
| GitHub | personal, **public** repo: GitHub Free offers environments on public repos only | code, workflow, environment |
| Grafana Cloud | Free, IRM for up to 3 users | stack `olivebus357`, EU (Ireland) |
| Scalr | Free, 50 runs/month | state and runs |
| 1Password | vault `terraform-scalr-poc` | every token |

## Tools

| Tool | Version | Why |
|---|---|---|
| OpenTofu | `1.13.1`, in `.opentofu-version` | Scalr runs Terraform only up to 1.5.x |
| Terraform | `1.15.8`, in `.terraform-version` | phase A and the CI, until the CI moves to OpenTofu |
| tenv | `4.15.1` | installs the pinned version and checks its signature |
| `grafana/grafana` | `~> 3.18`, locked at `3.25.9` | Grafana resources |
| `integrations/github` | `~> 6.13`, locked at `6.13.0` | GitHub environment, variables, secret |
| 1Password CLI | `2.40.0` | `op run` injects secrets at run time, never on disk |
| git / gh | `2.55.0` / `2.97.0` | |

## Setup

1. `make setup`, then turn on **1Password → Settings → Developer → Integrate with 1Password CLI**.
2. In Grafana Cloud, create a stack, then:
   - a service account `terraform-scalr` (role Admin) and its token: OpenTofu configures the stack with it;
   - a metrics token (stack **Details → InfluxDB → Configure**, scope `metrics:write`): the workflow pushes data with it.
3. On GitHub, create a fine-grained token for this repo only: **Administration** and **Environments**, read and write.
4. Store the 4 tokens in the 1Password vault: `grafana-terraform-scalr-token`, `grafana-github-metrics-write-token`, `github-fg-token`, `scalr-poc-token`.
5. Copy `.env.example` to `secrets.env.op` (git-ignored) and fill it: 1Password references only, never values.
6. `make init`, `make scalr-vars`, then `make plan` and `make apply`.

## Files

| File | Content |
|---|---|
| `versions.tf` | OpenTofu and provider versions, Scalr `backend "remote"` |
| `providers.tf` | empty `grafana` and `github` providers: they read their credentials from the environment |
| `variables.tf` | inputs; secrets are `sensitive` |
| `datasources.tf` | the stack's Prometheus data source, read and not created |
| `dashboards.tf` | folder "Scalr POC" and dashboard "GitHub push results (scalr)" |
| `alerts.tf` | email contact point and alert "main is broken" |
| `github.tf` | environment `env-poc-grafana-metrics` (main only), 2 variables, 1 secret |
| `.github/workflows/push-metrics.yml` | checks on every push; on `main`, sends the result to Grafana |
| `scripts/scalr_vars.py` | copies variables and secrets from 1Password to the Scalr workspace |

## Commands

| Command | What it does |
|---|---|
| `make setup` | install tenv, OpenTofu and the 1Password CLI |
| `make init` | download the providers and connect to the Scalr backend |
| `make plan` / `make apply` | run a plan or an apply on Scalr; apply asks for `yes` |
| `make migrate-state` | one time only: copy a local state to Scalr |
| `make scalr-vars` | copy the 9 variables (4 sensitive) to the Scalr workspace |
| `make check-token-{grafana,oncall,github,scalr}` | check one token from 1Password |
| `make push-metric` | send one test point to Grafana |

## Scalr in four ideas

- **Account → Environment → Workspace:** `kcelia.scalr.io` → `Environment-A` (`env-v0pejs6i46opjvptq`) → `scalr-learning` (`ws-v0peq0rl8d46th07e`). A workspace is one configuration with its state, variables and runs.
- **Provider vs backend:** providers create resources (Grafana, GitHub); the backend stores the state. Scalr is the backend, and with `execution-mode = remote` it also runs plan and apply.
- **Who starts a run:** CLI-driven (a terminal), VCS-driven (PRs and merges), API-driven (a script).
- **A remote run does not see the laptop's environment:** its variables and secrets must be set in the workspace.

## Findings

- **Scalr requires OpenTofu.** Terraform 1.6 and later use the BSL license, and Scalr runs Terraform only up to 1.5.x. OpenTofu read our Terraform 1.15.8 state without any change (`tofu plan`: No changes).
- **CLI-driven mode:**
  - ✅ plan and apply run on Scalr, and each run has an author, a time and a status;
  - ⚠️ the person who starts the run also approves it (`yes` in the terminal): there is no second review;
  - ⚠️ the local folder is uploaded, even uncommitted code: any branch can still be applied;
  - ⚠️ a runner starts for each stage, about 1 min 40 each here, for a one-second change (Free tier; it varies).
- **Secrets:**
  - POC: `make scalr-vars` copies them from 1Password to Scalr, as write-only sensitive variables. Nothing records who ran it: Scalr audit logs require the Enterprise plan.
  - Target, documented separately: tokens in AWS Secrets Manager, read by each run through OIDC with `ephemeral` resources, never stored in Scalr. Options: OpenTofu state encryption with AWS KMS, self-hosted Scalr agents in your own AWS.
- **State:** Scalr encrypts it at rest (AES-256), but users with the `state-versions:read` permission can still read the secrets inside.
- **Scalr token:** `terraform login` writes it in plain text on disk. We read `TF_TOKEN_kcelia_scalr_io` from 1Password instead.

## State encryption with OpenTofu (target, not tested yet)

OpenTofu can encrypt the state and the plans **before** it sends them to the backend (AES-GCM, `encryption` block). Scalr then stores an unreadable blob.

| Layer | Who can read the state in clear |
|---|---|
| Scalr at rest (AES-256, on by default) | Scalr, and users with `state-versions:read` |
| OpenTofu encryption, key in AWS KMS | only the AWS role allowed to use the key |

**Target design:** the key never leaves KMS. At each plan and apply, the run gets temporary AWS credentials through OIDC, asks KMS for the data key, and keeps it in memory only.

```hcl
terraform {
  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id = "<kms-key-id>"
      region     = "<region>"
      key_spec   = "AES_256"
    }
    method "aes_gcm" "state" {
      keys = key_provider.aws_kms.state
    }
    state { method = method.aes_gcm.state }
    plan  { method = method.aes_gcm.state }
  }
}
```

**What it needs:**
- an AWS role trusted by `https://scalr.io`, limited with `scalr.io:sub` = `account:kcelia:environment:Environment-A:workspace:scalr-learning`, and allowed `kms:GenerateDataKey` and `kms:Decrypt` on the key. The same role can read the tokens in Secrets Manager;
- a Scalr AWS provider configuration (OIDC) with `export_shell_variables`, so that OpenTofu itself receives the credentials. Only one such configuration per workspace;
- for the first apply, an `unencrypted` method as `fallback`, to read the old state; remove it afterwards.

**Limits:**
- Scalr's resource and output views stop working on encrypted workspaces.
- Losing the key means losing the state.
- It does not stop code that runs inside a run: approvals and permissions handle that.
- A passphrase key (PBKDF2) would have to be stored in Scalr. It only protects against state readers, so we skip it: restricting `state-versions:read` gives almost the same protection.

## Next steps

1. VCS-driven workspace: plan on PR, apply on merge to `main`, with approval.
2. Check that a laptop can no longer apply.
3. Drift detection: change an alert in the Grafana UI and wait for Scalr to report it.
4. Move the CI workflow to OpenTofu and delete `.terraform-version`.
5. `make plan` and `make apply` only need the Scalr token: give them their own env file.
6. With an AWS account: test OIDC, Secrets Manager with `ephemeral`, and state encryption with KMS.



VCS

worscape -> settings change cli to vsc
