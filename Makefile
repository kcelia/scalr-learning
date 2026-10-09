TF_VERSION := $(shell cat .terraform-version 2>/dev/null)
ENV_FILE := secrets.env.op
TF := op run --env-file $(ENV_FILE) -- terraform
REPO := scalr-learning

.PHONY: help setup check-token-grafana check-token-oncall check-token-github push-metric init plan apply

help: ## List the commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-20s %s\n", $$1, $$2}'

setup: ## Install tenv, the pinned Terraform version and the 1Password CLI
	@test -n "$(TF_VERSION)" || { echo "error: .terraform-version is missing or empty" >&2; exit 1; }
	@command -v tenv >/dev/null || brew install tenv
	@command -v op >/dev/null || brew install --cask 1password-cli
	tenv tf install $(TF_VERSION)
	terraform version
	op --version

$(ENV_FILE):
	@echo "error: $(ENV_FILE) is missing. Copy .env.example to $(ENV_FILE) and fill it in." >&2; exit 1

init: ## Download the providers and write .terraform.lock.hcl
	@## -input=false prevents Terraform from prompting you for input via the keyboard:
	terraform init -input=false

plan: $(ENV_FILE) ## Show what Terraform would change in Grafana and GitHub
	$(TF) plan

apply: $(ENV_FILE) ## Apply the changes to Grafana and GitHub, after confirmation
	$(TF) apply

check-token-grafana: $(ENV_FILE) ## Check that the Grafana token stored in 1Password works
	@op run --env-file $(ENV_FILE) -- sh -c 'code=$$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $$GRAFANA_AUTH" "$$GRAFANA_URL/api/folders"); echo "Grafana API: HTTP $$code"; test "$$code" = 200'

check-token-oncall: $(ENV_FILE) ## Check that the Grafana token also works on the OnCall API
	@op run --env-file $(ENV_FILE) -- sh -c 'code=$$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: $$GRAFANA_AUTH" -H "X-Grafana-URL: $$GRAFANA_URL" "$$GRAFANA_ONCALL_URL/api/v1/users/"); echo "OnCall API: HTTP $$code"; test "$$code" = 200'

check-token-github: $(ENV_FILE) ## Check that the GitHub token stored in 1Password can reach this repo
	@op run --env-file $(ENV_FILE) -- sh -c 'code=$$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $$GITHUB_TOKEN" "https://api.github.com/repos/$$GITHUB_OWNER/$(REPO)"); echo "GitHub API: HTTP $$code"; test "$$code" = 200'

push-metric: $(ENV_FILE) ## Send one test point (success=1) to Grafana Cloud metrics
	@op run --env-file $(ENV_FILE) -- sh -c 'code=$$(curl -s -o /dev/null -w "%{http_code}" -u "$$TF_VAR_grafana_metrics_instance_id:$$TF_VAR_grafana_metrics_write_token" --data-binary "github_push,repo=scalr-learning,source=laptop success=1" "$$TF_VAR_grafana_metrics_write_url"); echo "Metrics push: HTTP $$code"; test "$$code" -ge 200 -a "$$code" -lt 300'
