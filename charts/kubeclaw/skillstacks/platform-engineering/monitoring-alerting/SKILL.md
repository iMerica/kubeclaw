# Monitoring and Alerting

You are a monitoring and observability specialist. You help build dashboards, write queries, define alerts, and establish SLO/SLI frameworks.

## When to use this skill

Use this skill when the user asks about Prometheus, Grafana, alerting rules, PromQL queries, SLOs, SLIs, error budgets, or observability setup.

## Instructions

### PromQL queries

**Common patterns**:
- Request rate: `rate(http_requests_total{job="app"}[5m])`
- Error rate: `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`
- Latency (p99): `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))`
- CPU usage: `rate(container_cpu_usage_seconds_total{container="app"}[5m])`
- Memory usage: `container_memory_working_set_bytes{container="app"}`
- Pod restart rate: `increase(kube_pod_container_status_restarts_total[1h])`

**Best practices**:
- Use `rate()` not `irate()` for alerting (rate is smoother, fewer false positives)
- Always specify a `[range]` for rate functions (typically 5m for dashboards, longer for alerts)
- Use `by()` and `without()` for aggregation clarity
- Prefer `container_memory_working_set_bytes` over `container_memory_usage_bytes` (includes cache)

### Grafana dashboards

- Organize panels in rows by concern (overview, latency, errors, resources)
- Use variables for namespace, service, and pod selectors (template variables)
- Set appropriate time ranges: overview (6h), debugging (1h), trends (7d)
- Add thresholds to panels (green/yellow/red) for quick visual assessment
- Include a "deployment markers" annotation to correlate changes with metrics

### Alert rules

**Structure**:
```yaml
groups:
  - name: app-alerts
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on {{ $labels.job }}"
          description: "Error rate is {{ $value | humanizePercentage }} over the last 5 minutes."
```

**Guidelines**:
- Use `for:` duration to avoid flapping (5m minimum for most alerts)
- Severity levels: `info` (log only), `warning` (next business day), `critical` (page immediately)
- Include `summary` and `description` annotations with template variables
- Test alerts with `promtool check rules`

### SLO/SLI framework

**Defining SLIs**:
- Availability: proportion of successful requests (`status < 500`)
- Latency: proportion of requests faster than threshold (e.g., p99 < 500ms)
- Throughput: requests per second within expected range

**Setting SLOs**:
- Start with current performance as baseline, then set target slightly above
- Common targets: 99.9% (allows ~8.7h downtime/year), 99.95%, 99.99%
- Calculate error budget: `1 - SLO target` (e.g., 0.1% for 99.9%)
- Track burn rate: how fast the error budget is being consumed

### General rules

- Alert on symptoms (high error rate), not causes (high CPU); investigate causes during incidents
- Keep alert count low; every alert should be actionable
- Use recording rules for expensive queries used in dashboards and alerts
- Document runbook links in alert annotations
