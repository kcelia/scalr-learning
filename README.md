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
- POC: `make push-vars-to-scalr` copies the secrets from 1Password to Scalr, as write-only sensitive variables. Nothing records who ran it: Scalr audit logs require the Enterprise plan.
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

1. `make setup` installs the required tools.
1. In Grafana Cloud, create a stack, then:
   - a service account `terraform-scalr` (role Admin) and its token: OpenTofu configures the stack with it;
   - a metrics token (stack **Details → InfluxDB → Configure**, scope `metrics:write`): the workflow pushes data with it.
1. On GitHub, create a fine-grained token for this repo only: **Administration** and **Environments**, read and write.
1. Create a Scalr API token with `tofu login kcelia.scalr.io`. It writes the token in plain text to `~/.terraform.d/credentials.tfrc.json`: copy it to 1Password, then delete it from the file (if you keep it, `chmod 600` the file).
  - OpenTofu looks for the token in this order:
      1. the environment variable `TF_TOKEN_kcelia_scalr_io` (`TF_TOKEN_` + the host, dots replaced by underscores);
      2. `~/.terraform.d/credentials.tfrc.json`, written by `tofu login`, in plain text;
      3. a credentials helper.

    The POC uses the first one:
    ```make
    # The Makefile holds the 1Password reference, not the token
    SCALR_TOKEN_ENV := $(SCALR_TOKEN_VAR)=op://terraform-scalr-poc/scalr-poc-token/credential
    TF := $(SCALR_TOKEN_ENV) op run -- tofu
    ```
1. Store the 4 tokens in the 1Password vault `terraform-scalr-poc`: `grafana-terraform-scalr-token`, `grafana-github-metrics-write-token`, `github-fg-token`, `scalr-poc-token`.
1. Copy `.env.example` to `secrets.env.op` (git-ignored) and fill it: 1Password references only, never values.
1. `make push-vars-to-scalr`
  - copies the variables to the Scalr workspace through the Scalr API with the values `op run` reads from 1Password and `secrets.env.op`.
  - Run it once, then again whenever a value changes
  - Variables in Scalr: A variable is **declared** in the code (`variable` block) and gets its **value** from the workspace, set in one of 3 ways:
    - the Scalr UI: **Workspace → Variables → Create variable**;
    - the Scalr API: what `scripts/push_vars_to_scalr.py` does;
    - the Scalr Terraform provider: `scalr_variable`.

  - Scalr has [2 categories of variables](https://docs.scalr.io/docs/variables):
    - Terrafrom: fills the `variable` block of the same name
    - Shell: exports it as an environment variable

  - <!> Sensitive variables: Scalr masks them in the UI and the API. The state still stores them in clear once a resource uses them.

![Terraform variables in the workspace: sensitive values are masked](image-10.png)

### Scenario 1: CLI-driven (commit `00a4d4d`)

1. Add the `backend "remote"` block to `versions.tf`: Scalr host, environment, workspace.
2. `make init`, then `make migrate-state`: copy the local state to the workspace `scalr-learning` (one time only).
3. `make push-vars-to-scalr`: copy the 9 variables (4 sensitive) to the workspace.
4. `make plan`, then `make apply` (confirmed with `yes`): both run on Scalr.

### Scenario 2: VCS-driven + secrets in Scalr env (PR #1, commit `86a7417`)

1. **Connect the workspace to GitHub:** **Workspace → Settings → Source → Configuration source: VCS**: repository, branch `main`, trigger "any change", auto-apply off. Same workspace, same state.
   ![Workspace settings in VCS mode](image-1.png)
2. **Make a change:** add the Terraform variable `poc_fake_secret` (sensitive) in the Scalr UI, and the GitHub secret `POC_FAKE_SECRET` that uses it (`github_actions_environment_secret.poc_fake`).
3. **Plan:**
   - A plan compares resources (code, state, real services), not variables: as long as no resource used `poc_fake_secret`, the plan said *No changes*.
   - `make plan` from the laptop shows `value = (sensitive value)`:
     ![Plan in the terminal](image-12.png)
   - The terminal prints the link to the run in Scalr. A plan started from the laptop is a dry run: it cannot be applied.
     ![Link to the run, printed by make plan](image-13.png)
     ![The same plan in Scalr](image-14.png)
   - Scalr lists every run under **Runs → History**; runs started from the laptop show the trigger `CLI`.
     ![Runs started from the laptop](image-15.png)
4. **Apply:**
   - `make apply` from the laptop is refused: *Apply not allowed for workspaces with a VCS connection*.
   - Push or merge to `main`: Scalr runs a plan, then waits for approval (auto-apply off). Approve it in **Runs → Queue** or on the run page.
     ![Run waiting for approval in the queue](image-17.png)
     ![Workspace dashboard: the latest run requires approval](image-16.png)
     ![Run page: the plan to approve](image-18.png)
   - On GitHub, the commit lists every check: Scalr's plan and the two `push-metrics` jobs.
     ![Checks on the commit](image-19.png)
   - The run executes on Scalr's runners, not on GitHub: GitHub only shows the status Scalr sends it (for example *Pending – Planning*). The logs stay in Scalr; **Details** links to them.
   - When the plan has no changes, the run stops after the plan: no approval and no apply, whether auto-apply is on or off.

5. ⏳ **Check the state:** after the apply, the state should hold the value of `poc_fake_secret` in clear, in the `value` attribute of `github_actions_environment_secret.poc_fake` (**Workspace → States**; download the state version if the UI masks it).

**What `make plan` sends to Scalr**
- `tofu` packs the local folder into an archive (a *slug*) and uploads it; the Scalr runner runs the plan from that archive, uncommitted code included.
- Only `.terraformignore` filters the archive, not `.gitignore`. Without it, everything except `.git/` and `.terraform/` was uploaded, git-ignored files included: `secrets.env.op`, the screenshots, any local `*.tfstate`.
- The repo's `.terraformignore` is an allowlist: it excludes everything, then keeps only what OpenTofu reads.
  ```
  *
  !*.tf
  !.terraform.lock.hcl
  ```
- Tested with go-slug `v0.16.8`, the library OpenTofu `1.13.1` uses to build the archive: the archive now holds only the 7 `.tf` files and `.terraform.lock.hcl`.
- If the code starts reading another file (a template, a local module), add it to `.terraformignore`: otherwise the run fails, because the file is missing on the runner.


Secrets in this scenario:
- See the variables of the brute state:
  - in Scalr UI:  Chaque ligne est une version du state
  ![alt text](image-20.png)
  - via terminal: ` tofu state pull` récupère la dernière version
  `! (umask 077 &&
  TF_TOKEN_kcelia_scalr_io=op://terraform-scalr-poc/scalr-poc-token/credential op run -- tofu state pull > ~/Downloads/scalr-learning.tfstate)`


### Scenario 2: VCS-driven + secrets in AWS secret manager


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
| `github.tf` | environment `env-poc-grafana-metrics` (main only), 2 variables, 2 secrets (one is the fake `POC_FAKE_SECRET`) |
| `.github/workflows/push-metrics.yml` | checks on every push; on `main`, sends the result to Grafana |
| `scripts/push_vars_to_scalr.py` | copies variables and secrets from 1Password to the Scalr workspace |
| `.terraformignore` | allowlist of what `tofu` uploads to Scalr: the `.tf` files and `.terraform.lock.hcl` |

| Command | What it does |
|---|---|
| `make setup` | install tenv, OpenTofu and the 1Password CLI |
| `make init` | download the providers and connect to the Scalr backend |
| `make plan` | run a plan of the **local** code on Scalr (allowed in both modes) |
| `make apply` | CLI-driven only. Refused once the workspace is VCS-driven |
| `make migrate-state` | one time only: copy a local state to Scalr |
| `make push-vars-to-scalr` | copy the 9 variables (4 sensitive) to the Scalr workspace |
| `make check-token-{grafana,oncall,github,scalr}` | check one token from 1Password |
| `make push-metric` | send one test point to Grafana |

