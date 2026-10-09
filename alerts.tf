# Contact point that emails the alerts to var.alert_email.
resource "grafana_contact_point" "email" {
  name = "poc-email"

  email {
    addresses = [var.alert_email]
  }
}

# Alerts about the Terraform checks that the workflow runs on every push to main.
resource "grafana_rule_group" "github_push" {
  name             = "GitHub push"
  folder_uid       = grafana_folder.poc.uid
  interval_seconds = 60

  rule {
    name           = "main is broken"
    condition      = "C"
    for            = "0s"
    no_data_state  = "OK"
    exec_err_state = "Alerting"

    # Send this alert to the email contact point instead of the stack's default ("empty", no destination).
    notification_settings {
      contact_point = grafana_contact_point.email.name
    }

    annotations = {
      summary = "The last Terraform checks on main failed. Fix main to resolve this alert."
    }

    labels = {
      service  = "github-push"
      severity = "critical"
      team     = "poc"
    }

    # A: last result the workflow sent for main within 24 hours (1 = success, 0 = failure).
    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.metrics.uid
      relative_time_range {
        from = 86400
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "last_over_time(github_push_success{repo=\"scalr-learning\", branch=\"main\"}[24h])"
        instant = true
      })
    }

    # B: keep one number per series.
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "B"
        type       = "reduce"
        expression = "A"
        reducer    = "last"
      })
    }

    # C: fire when that number is below 1, so when the last checks on main failed.
    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "B"
        conditions = [{ evaluator = { type = "lt", params = [1] } }]
      })
    }
  }
}
