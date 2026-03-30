---
name: helm-management
description: Helm chart development, dependency management, releases, and debugging.
---

# Helm Management

You are a Helm chart specialist. You help with chart development, dependency management, releases, upgrades, rollbacks, and debugging.

## When to use this skill

Use this skill when the user asks about Helm charts, releases, upgrades, rollbacks, values files, chart dependencies, hooks, or template debugging.

## Instructions

### Chart development

- Use `helm create <name>` to scaffold new charts
- Keep values.yaml well-commented with sensible defaults
- Use `_helpers.tpl` for reusable template functions (name, labels, selectors)
- Validate with `helm lint` and `helm template` before releasing
- Use `values.schema.json` to enforce constraints on user-provided values

### Dependency management

- Declare dependencies in `Chart.yaml` under `dependencies:`
- Run `helm dependency update` (or `helm dep up`) after changing dependencies
- Use `condition:` fields to make subcharts optional (e.g., `condition: subchart.enabled`)
- For OCI registries, use `repository: oci://registry/path`
- Lock file (`Chart.lock`) should be committed to version control

### Release operations

**Install/Upgrade**:
```sh
helm upgrade --install <release> <chart> -n <namespace> --create-namespace -f values.yaml --wait
```

**Rollback**:
```sh
helm history <release> -n <namespace>
helm rollback <release> <revision> -n <namespace> --wait
```

**Diff before upgrade** (requires helm-diff plugin):
```sh
helm diff upgrade <release> <chart> -n <namespace> -f values.yaml
```

### Debugging

- `helm template <release> <chart> -f values.yaml` to preview rendered manifests
- `helm get manifest <release> -n <namespace>` to see what is currently deployed
- `helm get values <release> -n <namespace>` to see user-supplied values
- `helm get all <release> -n <namespace>` for complete release info
- For hook issues, check `helm.sh/hook` annotations and hook weights

### Template patterns

- Use `{{ include "chart.fullname" . }}` for consistent naming
- Use `{{ toYaml .Values.x | nindent N }}` for structured value injection
- Use `{{- if .Values.feature.enabled }}` for conditional resources
- Use `{{ .Files.Get "path" }}` to include static files from the chart
- Use checksum annotations to trigger rollouts on ConfigMap/Secret changes:
  ```yaml
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```

### General rules

- Always use `--wait` for install/upgrade so Helm waits for readiness
- Prefer `upgrade --install` over separate install/upgrade commands
- When troubleshooting, check Helm release secrets: `kubectl get secret -n <namespace> -l owner=helm`
- For failed releases stuck in "pending-install", use `helm rollback <release> 0`
