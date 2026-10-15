#!/usr/bin/env python3
"""Copy the workspace variables from the environment (filled by `op run` from 1Password) to Scalr."""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass


@dataclass(frozen=True)
class Variable:
    """One Scalr variable: its key, how the run receives it, and whether its value is hidden."""

    key: str
    category: str  # "terraform" fills a `variable` block; "shell" is exported as an environment variable.
    sensitive: bool


VARIABLES: tuple[Variable, ...] = (
    Variable("GRAFANA_URL", "shell", False),
    Variable("GRAFANA_AUTH", "shell", True),
    Variable("GRAFANA_ONCALL_URL", "shell", False),
    Variable("GITHUB_OWNER", "shell", False),
    # GITHUB_TOKEN is now read from AWS Secrets Manager at each run (secrets.tf), no longer copied to Scalr.
    # Variable("GITHUB_TOKEN", "shell", True),
    Variable("grafana_metrics_write_url", "terraform", False),
    Variable("grafana_metrics_instance_id", "terraform", False),
    Variable("grafana_metrics_write_token", "terraform", True),
    Variable("alert_email", "terraform", True),
)


class ScalrClient:
    """Minimal client for the Scalr IaCP v3 API, authenticated with the token Terraform also uses."""

    def __init__(self, host: str) -> None:
        token_env = "TF_TOKEN_" + host.replace(".", "_")
        token = os.environ.get(token_env)
        if not token:
            raise SystemExit(f"error: {token_env} is not set: run this through `make push-vars-to-scalr`")
        self._api = f"https://{host}/api/iacp/v3"
        self._token = token

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        """Send one request and return the decoded JSON; exit on any non-2xx status."""
        req = urllib.request.Request(
            f"{self._api}{path}",
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Accept": "application/vnd.api+json",
                "Content-Type": "application/vnd.api+json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as err:
            raise SystemExit(f"error: {method} {path} returned HTTP {err.code}") from err
        return json.loads(raw) if raw else {}


def local_value(var: Variable) -> str:
    """Read the variable's value from the environment, where `op run` put it."""
    name = var.key if var.category == "shell" else f"TF_VAR_{var.key}"
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"error: {name} is not set in secrets.env.op")
    return value


def workspace_id(client: ScalrClient, name: str) -> str:
    """Return the ID of the workspace called `name`, which must exist exactly once."""
    data = client.request("GET", f"/workspaces?filter%5Bname%5D={name}")["data"]
    if len(data) != 1:
        raise SystemExit(f"error: expected one Scalr workspace named {name}, found {len(data)}")
    return data[0]["id"]


def existing_variables(client: ScalrClient, ws_id: str) -> dict[tuple[str, str], str]:
    """Map (key, category) to variable ID, for the variables defined directly on the workspace."""
    data = client.request("GET", f"/vars?filter%5Bworkspace%5D={ws_id}&page%5Bsize%5D=100")["data"]
    found: dict[tuple[str, str], str] = {}
    for item in data:
        owner = (item.get("relationships", {}).get("workspace", {}).get("data") or {}).get("id")
        if owner == ws_id:
            found[(item["attributes"]["key"], item["attributes"]["category"])] = item["id"]
    return found


def create_variable(client: ScalrClient, ws_id: str, attributes: dict) -> None:
    """Create a variable on the workspace."""
    relationships = {"workspace": {"data": {"type": "workspaces", "id": ws_id}}}
    client.request("POST", "/vars", {"data": {"type": "vars", "attributes": attributes, "relationships": relationships}})


def update_variable(client: ScalrClient, var_id: str, attributes: dict) -> None:
    """Replace the value and flags of an existing variable."""
    client.request("PATCH", f"/vars/{var_id}", {"data": {"type": "vars", "id": var_id, "attributes": attributes}})


def main() -> None:
    """Read every value first, then create or update each variable; print keys only, never values."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="Scalr account host, e.g. kcelia.scalr.io")
    parser.add_argument("--workspace", required=True, help="Scalr workspace name")
    args = parser.parse_args()

    values = {var: local_value(var) for var in VARIABLES}
    client = ScalrClient(args.host)
    ws_id = workspace_id(client, args.workspace)
    existing = existing_variables(client, ws_id)

    for var, value in values.items():
        attributes = {"key": var.key, "value": value, "category": var.category, "sensitive": var.sensitive, "hcl": False}
        var_id = existing.get((var.key, var.category))
        if var_id:
            update_variable(client, var_id, attributes)
        else:
            create_variable(client, ws_id, attributes)
        flag = " (sensitive)" if var.sensitive else ""
        print(f"{'updated' if var_id else 'created':8} {var.category:9} {var.key}{flag}")


if __name__ == "__main__":
    main()
