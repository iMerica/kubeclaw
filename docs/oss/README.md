# OpenClaw OSS Chart — Install Guide

## Prerequisites

- Kubernetes 1.25+
- Helm 3.12+
- A `ReadWriteOnce`-capable StorageClass (default cluster StorageClass is used if none specified)
- An OpenClaw Gateway image accessible from your cluster

## Quick Install

```sh
helm repo add kubeclaw https://iMerica.github.io/kubeclaw
helm repo update

helm install my-kubeclaw kubeclaw/kubeclaw \
  --namespace kubeclaw \
  --create-namespace \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=<strong-token-here>
```

## Day-0: First Connect

After install, the Gateway runs at `ClusterIP:18789`. Access via port-forward:

```sh
kubectl port-forward -n kubeclaw svc/my-kubeclaw 18789:18789
# Now connect your browser or CLI to http://localhost:18789
```

For external access, enable Ingress (see below).

## Configuration Reference

See [`values.yaml`](../../charts/kubeclaw/values.yaml) for all options with inline documentation.

### Minimum required values

| Key | Required | Notes |
|-----|----------|-------|
| `secret.data.OPENCLAW_GATEWAY_TOKEN` | Yes | Strong random string. Treat as a password. |
| `image.repository` | Yes | Gateway container image repository |
| `image.tag` | Yes | Pin to a specific tag in production |

### Storage

The Gateway stores all state under `/home/node/.openclaw`. A PVC is created automatically by the StatefulSet.

```yaml
persistence:
  size: 10Gi
  storageClass: my-storage-class  # leave empty for cluster default
```

**Split volumes** (separate PVCs for state vs workspace):

```yaml
persistence:
  splitVolumes: true
  size: 5Gi
  workspace:
    size: 10Gi
```

### Enabling Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  host: openclaw.example.com
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  tls:
    - secretName: openclaw-tls
      hosts:
        - openclaw.example.com
```

> **WebSocket timeouts**: The Control UI uses long-lived WebSocket connections. The default ingress-nginx proxy timeout (60s) will disconnect idle WebSocket sessions. The annotations above set timeouts to 3600s.

### Desired Config (GitOps)

Mount an `openclaw.json` (JSON5) config via ConfigMap, applied at pod start:

```yaml
config:
  desired: |
    {
      "gateway": { "host": "0.0.0.0" },
      "tools": { "exec": { "enabled": true } }
    }
  mode: merge  # or "overwrite"
```

- `merge`: applies JSON merge-patch onto the existing config (preserves runtime edits)
- `overwrite`: replaces the entire config file

A config change triggers a rolling restart (checksum annotation in pod template).

### Chromium Sidecar

Add a remote Chromium browser accessible via CDP (pod-internal only):

```yaml
chromium:
  enabled: true
  image:
    repository: browserless/chromium
    tag: latest
```

The Gateway config is automatically patched to set `browser.profiles.chromium.cdpUrl: "http://127.0.0.1:9222"` — add this to your `config.desired` or set it at runtime.

> **Security note**: Chromium in containers often requires `--no-sandbox`. For stronger isolation, set `pod.runtimeClassName: gvisor`.

### Using an Existing Secret

Instead of having the chart create a Secret, reference one you manage:

```yaml
secret:
  create: false
  existingSecretName: my-openclaw-secret
```

The referenced Secret must contain at least `OPENCLAW_GATEWAY_TOKEN`.

## Day-1: Health and Diagnostics

### Check status

```sh
kubectl -n openclaw exec -it statefulset/my-openclaw -- node dist/index.js status
kubectl -n openclaw exec -it statefulset/my-openclaw -- node dist/index.js gateway status
kubectl -n openclaw exec -it statefulset/my-openclaw -- node dist/index.js doctor
kubectl -n openclaw exec -it statefulset/my-openclaw -- node dist/index.js channels status --probe
```

### Enable diagnostics CronJob

```yaml
diagnostics:
  enabled: true
  schedule: "0 * * * *"
```

Output is written to pod logs. Pipe to your logging stack.

## Security Baseline

- The Gateway runs as a non-root user (`runAsNonRoot: true`, `fsGroup: 1000`).
- `allowPrivilegeEscalation: false` is set on all containers.
- Keep `OPENCLAW_GATEWAY_TOKEN` strong and secret. It authenticates Control UI access and health probes.
- Do not expose port 18789 without authentication. The canvas host serves arbitrary HTML/JS.
- If enabling Ingress, use TLS and keep Gateway token auth enabled.

## Exec Isolation

For stronger container runtime isolation (gVisor, Kata Containers):

```yaml
pod:
  runtimeClassName: gvisor  # RuntimeClass must exist in the cluster
```

This chart does not install runtime implementations.

## NetworkPolicy

Basic NetworkPolicy (opt-in):

```yaml
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    kubernetes.io/metadata.name: ingress-nginx
```

For FQDN-based egress control, see the Ultra chart.

## Upgrade

```sh
helm upgrade my-kubeclaw kubeclaw/kubeclaw -n kubeclaw -f my-values.yaml
```

The StatefulSet uses `replicas: 1` enforced by JSON schema. The PVC persists across upgrades.

## Uninstall

```sh
helm uninstall my-kubeclaw -n kubeclaw
# PVCs are NOT deleted by default. Delete manually if desired:
kubectl -n kubeclaw delete pvc -l app.kubernetes.io/instance=my-kubeclaw
```
