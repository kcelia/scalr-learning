# Scalr POC

Goal: find out whether [Scalr](https://scalr.com) is a good option to:
- **store the Terraform state file**;
- **run `plan` and `apply` for the whole team**, instead of on each engineer's laptop.

Current setup:
- The Terraform state file is stored in an AWS S3 bucket.
- Terraform reaches the bucket with static AWS access keys, kept in 1Password and injected on the laptop at each run (`op run`).
- `plan` and `apply` run on each engineer's laptop.
- No drift detection: a change made directly in a service, for example in the Grafana UI, goes unnoticed until someone runs a `plan`.

## Accounts and tools

| Account | Plan | Used for |
|---|---|---|
| GitHub | personal, **public** repo: GitHub Free offers environments on public repos only | code, workflow, environment |
| Grafana Cloud | Free, IRM for up to 3 users | stack `olivebus357`, EU (Ireland) |
| Scalr | Free, 50 runs/month | state and runs |
| 1Password | vault `terraform-scalr-poc` | every token |

| Tool | Version | Why |
|---|---|---|
| OpenTofu | `1.13.1`, in `.opentofu-version` | Scalr runs Terraform only up to 1.5.x |
| Terraform | `1.15.8`, in `.terraform-version` | phase A and the CI, until the CI moves to OpenTofu |
| tenv | `4.15.1` | installs the pinned version and checks its signature |
| `grafana/grafana` | `~> 3.18`, locked at `3.25.9` | Grafana resources |
| `integrations/github` | `~> 6.13`, locked at `6.13.0` | GitHub environment, variables, secret |
| 1Password CLI | `2.40.0` | `op run` injects secrets at run time, never on disk |

## The use-case we want to build

```
push ──▶ workflow push-metrics: fmt + init -backend=false + validate
           └─ on main only ──▶ success=1 or 0 ──▶ Grafana Cloud metrics
                                                    ├─▶ dashboard "GitHub push results"
                                                    └─▶ alert "main is broken" ──▶ email
```


## Scalr

- Scalr is a SaaS platform for Terraform and OpenTofu, like HCP Terraform.
It replaces the laptop and the S3 bucket:
- it stores, locks and versions the **state**;
- it runs `plan` and `apply` on its own **runners**;
- it adds **approvals**, **run history** (author, time, status, logs), **permissions** and **drift detection**.

In Terraform terms, *Providers* create resources (Grafana, GitHub); the *backend* stores the state. Scalr is the backend, and with `execution-mode = remote` it also runs plan and apply.

- **Who starts a run:** CLI-driven (a terminal), VCS-driven (PRs and merges), API-driven (a script).


### How Scalr is organized

| Level | What it is | In this POC |
|---|---|---|
| **Account** | the company space | `kcelia` (`https://kcelia.scalr.io`) |
| **Environment** | a group of workspaces sharing the same rules: access, variables, policies, drift detection | `Environment-A` (`env-v0pejs6i46opjvptq`) |
| **Workspace** | one configuration with its state, variables, settings and run history | `scalr-learning` (`ws-v0peq0rl8d46th07e`) |

### What starts a run (workspace type)

The type can be changed at any time: the POC moved its workspace from CLI-driven to VCS-driven without moving the state.


| Type | Trigger | Example |
|---|---|---|
| **CLI-driven** | `tofu plan` or `tofu apply` in a terminal; the local folder is uploaded to Scalr |
| **VCS-driven** | the Git repository: a PR starts a plan; a merge to the branch starts a plan, then an apply after approval | the plan shows as a GitHub check on the PR |
| **API-driven** | a script uploads the code through the Scalr API | an existing pipeline decides when to send the code |
| **No-code** | a form in the Scalr UI: pick a module from the Scalr registry, fill in its variables | someone who does not write Terraform deploys a standard module |

**CLI-driven mode**
- ✅ plan and apply are triggered on the laptop but actual execution on on Scalr's runners and each run is tracked (author, time, status...)
- ⚠️ The person who starts the run also approves it (`yes` in the terminal): there is no second review.
- ⚠️ The local folder is uploaded, even uncommitted code: any branch can still be applied.

**VCS-driven mode**
- ✅ A PR starts a plan-only run, shown on the PR as a GitHub check.
- ✅ A push or merge to `main` starts a plan, which waits for approval in Scalr (auto-apply off). The commit status shows the result.
- ✅ `make apply` from a laptop is refused: *"Apply not allowed for workspaces with a VCS connection"*.
- ⚠️ `make plan` from a laptop still works: it runs local, uncommitted code with the workspace secrets. Limit who can start runs.
- ⚠️ Trigger "any change": a README-only PR also used a run. Trigger patterns must cover every file the code reads (for example `*.tf` and `templates/**`).
- Scalr can connect to GitHub in two ways: **OAuth** (Scalr acts as the user and gets all their access, including other organizations they belong to) or a **GitHub App** (Scalr has its own identity, installed only on selected repositories, with limited permissions). Prefer the GitHub App.
- To find a run: on GitHub, the commit or PR check → **Details**; in Scalr, **Workspace → Runs**.

Scalr also offers **API-driven** workspaces (a script uploads the code through the Scalr API) and **No-code** workspaces (a form in the Scalr UI deploys a module from the Scalr registry). Not tested in this POC.

![Scalr plan as a check on the PR](image-2.png)
![Scalr status on a commit pushed to main](image-3.png)

### Execution mode in Scarl

| Mode | Where `plan` and `apply` run | What Scalr provides |
|---|---|---|
| **Remote** (default) | on Scalr's runners | state, variables, provider configurations, policies, approvals |
| **Local** ("state storage only") | on the laptop | the state only; these runs are free, but Scalr variables, provider configurations and policies are not available |

> A remote run does not see the laptop's environment. Every variable and secret the code needs must be set in the workspace.

**Secrets and state**
- POC: `make scalr-vars` copies the secrets from 1Password to Scalr, as write-only sensitive variables. Nothing records who ran it: Scalr audit logs require the Enterprise plan.
- Target: tokens in AWS Secrets Manager, read by each run through OIDC with `ephemeral` resources, never stored in Scalr. Options: OpenTofu state encryption with AWS KMS, self-hosted Scalr agents in your own AWS.
- Scalr encrypts the state at rest (AES-256), but users with the `state-versions:read` permission can still read the secrets inside.
- `terraform login` writes the Scalr token in plain text on disk. We read `TF_TOKEN_kcelia_scalr_io` from 1Password instead.

### Drift

- **A plan compares 3 things:** the code (what you want), the state (what Terraform manages) and the real services, read at each plan (`Refreshing state…`).
- A **drift** is a gap between the code and the real services, caused by a change made outside Terraform (a click in the Grafana UI, a direct API call, or the service itself).
- Any plan finds it. Scalr's drift detection adds a **scheduled** plan, set **per environment** (daily or weekly). These runs are free; Revert and Sync runs count. Options: *Ignore*, *Sync State* (the state accepts reality), *Revert Infrastructure* (the code wins).
- <!> Grafana locks alert rules and contact points created by Terraform ("Provisioned"): no edit or pause in the UI, unless `disable_provenance = true`. The lock blocks the UI only, not the API. Dashboards are not locked.

When Scalr detects drift, such as manual changes made through a provider’s UI, you can choose “Revert Infrastructure”. Scalr then triggers a plan & apply run that rolls these changes back to match the Terraform/OpenTofu configuration.

![alt text](image-6.png)
In VCS mode, you need to approve the run.
![alt text](image-5.png)

### Scalr needs OpenTofu
- Since version 1.6 (August 2023), Terraform uses the **Business Source License (BSL)**, which forbids competitors of HashiCorp's own platform from running it. Scalr is one of them.
- Scalr therefore runs Terraform only **up to 1.5.7**, the last open-source (MPL 2.0) version.
- For newer versions, Scalr uses **OpenTofu**: the open-source fork of Terraform, created from Terraform 1.5 and hosted by the Linux Foundation (CNCF project since April 2025). Same HCL, same providers, `tofu` instead of `terraform`.
- Prod uses Terraform `1.15.8`, so the POC switched to OpenTofu.

> **Finding:** adopting Scalr means migrating prod from Terraform to OpenTofu, or going back to Terraform 1.5.7.

## Setup

### Common steps

1. `make setup` to install required packages, then turn on **1Password → Settings → Developer → Integrate with 1Password CLI**.
2. In Grafana Cloud, create a stack, then:
   - a service account `terraform-scalr` (role Admin) and its token: OpenTofu configures the stack with it;
   - a metrics token (stack **Details → InfluxDB → Configure**, scope `metrics:write`): the workflow pushes data with it.
3. On GitHub, create a fine-grained token for this repo only: **Administration** and **Environments**, read and write.
4. Store the 4 tokens in the 1Password vault: `grafana-terraform-scalr-token`, `grafana-github-metrics-write-token`, `github-fg-token`, `scalr-poc-token`.
5. Copy `.env.example` to `secrets.env.op` (git-ignored) and fill it: 1Password references only, never values.
### Scenario 1: CLI-driven (commit `00a4d4d`)

1. Add the `backend "remote"` block to `versions.tf`: Scalr host, environment, workspace.
2. `make init`, then `make migrate-state`: copy the local state to the workspace `scalr-learning` (one time only).
3. `make scalr-vars`: copy the 9 variables (4 sensitive) to the workspace.
4. `make plan`, then `make apply` (confirmed with `yes`): both run on Scalr.

### Scenario 2: VCS-driven (PR #1)

1. In Scalr, create a GitHub VCS provider (account level, OAuth).
2. **Workspace → Settings → Source → Configuration source: VCS**: repository, branch `main`, trigger "any change", auto-apply off. Same workspace, same state.
3. Open PR #1 (dashboard renamed), merge it, then approve the run in Scalr.
4. Push a commit straight to `main` (`937e21e`).
5. Run `make apply` from the laptop: refused.

![Workspace settings in VCS mode](image-1.png)

### Drift detection (both scenarios)

**Environment settings → Drift detection → Daily**.


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

**Limits:** Scalr's resource and output views stop working; losing the key means losing the state; it does not stop code that runs inside a run. A passphrase key (PBKDF2) would be stored in Scalr and protect only against state readers: restricting `state-versions:read` gives almost the same result.

## Next steps

1. Drift detection: check that the scheduled run reports the dashboard drift, then **Revert Infrastructure**.
2. Scalr permissions: who can start runs, approve applies and read the state.
3. Move the CI workflow to OpenTofu and delete `.terraform-version`.
4. `make plan` only needs the Scalr token: give it its own env file.
5. With an AWS account: test OIDC, Secrets Manager with `ephemeral`, and state encryption with KMS.

## What Scalr brings out of the box for Terraform and OpenTofu runs

| Capability | What Scalr does | POC |
|---|---|---|
| Remote runs | runs plan and apply on its runners (or on self-hosted agents), never on a laptop | ✅ tested |
| State backend | stores, locks and versions the state; encrypted at rest | ✅ tested |
| Run history | author, time, status and logs of every run | ✅ tested |
| VCS workflow | plan on every PR (GitHub check), apply on merge to the branch, CLI applies blocked | ✅ tested |
| Approvals | an apply waits for a human (UI or `/scalr approve` on the PR) | ✅ tested (UI) |
| Variables | Terraform and shell variables; sensitive ones are write-only; inherited account → environment → workspace | ✅ tested |
| Drift detection | scheduled plans per environment; Ignore, Sync State or Revert Infrastructure | ⏳ |
| Notifications | Slack: approval needed, run result, drift detected | 📄 documented |
| Policies | OPA policy checks on plans | 📄 documented |
| Permissions | fine-grained roles, for example `runs:apply`, `state-versions:read` | 📄 documented |
| Cloud credentials | OIDC to AWS, GCP and Azure: temporary credentials per run, no stored key | 📄 documented |
| Audit log | account-wide activity log | Enterprise plan only |

**What it does not do for you:**
- run Terraform 1.6 or later: you need OpenTofu;
- remove the secrets Grafana and GitHub need: they are copied into Scalr, or read from a secret manager through OIDC;
- fix a drift on its own: a human chooses Sync or Revert;
- stay fast and unlimited on the Free plan: 50 runs per month, and a runner start at each stage.


![alt text](image-4.png)




## Files and commands

| File | Content |
|---|---|
| `versions.tf` | OpenTofu and provider versions, Scalr `backend "remote"` |
| `providers.tf` | empty `grafana` and `github` providers: they read their credentials from the environment |
| `variables.tf` | inputs; secrets are `sensitive` |
| `datasources.tf` | the stack's Prometheus data source, read and not created |
| `dashboards.tf` | folder "Scalr POC" and dashboard "GitHub push results" |
| `alerts.tf` | email contact point and alert "main is broken" |
| `github.tf` | environment `env-poc-grafana-metrics` (main only), 2 variables, 1 secret |
| `.github/workflows/push-metrics.yml` | checks on every push; on `main`, sends the result to Grafana |
| `scripts/scalr_vars.py` | copies variables and secrets from 1Password to the Scalr workspace |

| Command | What it does |
|---|---|
| `make setup` | install tenv, OpenTofu and the 1Password CLI |
| `make init` | download the providers and connect to the Scalr backend |
| `make plan` | run a plan of the **local** code on Scalr (allowed in both modes) |
| `make apply` | CLI-driven only. Refused once the workspace is VCS-driven |
| `make migrate-state` | one time only: copy a local state to Scalr |
| `make scalr-vars` | copy the 9 variables (4 sensitive) to the Scalr workspace |
| `make check-token-{grafana,oncall,github,scalr}` | check one token from 1Password |
| `make push-metric` | send one test point to Grafana |

