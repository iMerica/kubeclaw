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

## Verify

```sh
# Build subchart dependencies (required when litellm.enabled=true)
helm dependency build charts/kubeclaw

# Lint (default)
helm lint charts/kubeclaw

# Lint with LiteLLM enabled
helm lint charts/kubeclaw \
  --set litellm.enabled=true \
  --set litellm.masterkey=sk-test-key

# Dry-run (default)
helm template kubeclaw charts/kubeclaw \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  | kubectl apply --dry-run=client -f -

# Confirm replica enforcement (must error)
helm template kubeclaw charts/kubeclaw --set replicaCount=2

# Confirm masterkey is required when litellm.enabled=true (must error)
helm template kubeclaw charts/kubeclaw --set litellm.enabled=true
```

## Day-0: First Connect

After install, the Gateway runs at `ClusterIP:18789`. Access via port-forward:

```sh
kubectl port-forward -n kubeclaw svc/my-kubeclaw 18789:18789
```

**Important**: Generate an authenticated URL before opening the UI:
```sh
kubectl -n kubeclaw exec statefulset/my-kubeclaw -- \
  node dist/index.js dashboard --no-open
```

Use the generated URL (with token) instead of plain localhost:18789. Opening without the token will show "unauthorized" errors.

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

### LiteLLM Proxy (optional)

The chart can deploy a [LiteLLM](https://docs.litellm.ai/) proxy alongside the Gateway. When enabled, the chart injects `OPENAI_API_BASE` into the Gateway container so that all LLM SDK calls route through the proxy transparently.

**Benefits:** per-agent virtual keys with budget caps, model fallback routing, semantic caching, and content guardrails, all declared in `values.yaml`.

#### Enable

Pull the subchart before the first install or upgrade:

```sh
helm dependency build charts/kubeclaw
```

Minimum values:

```yaml
litellm:
  enabled: true
  masterkey: sk-your-strong-key   # must start with sk-

  # provider API keys — reference an existing Secret
  environmentSecrets:
    - my-llm-provider-keys        # must contain e.g. ANTHROPIC_API_KEY

  proxy_config:
    model_list:
      - model_name: "anthropic/claude-opus-4-6"
        litellm_params:
          model: "anthropic/claude-opus-4-6"
          api_key: "os.environ/ANTHROPIC_API_KEY"
    litellm_settings:
      drop_params: true
    general_settings:
      master_key: "os.environ/PROXY_MASTER_KEY"
```

The `masterkey` value (or a reference via `masterkeySecretName`) is enforced by the chart's JSON schema. `helm install` will fail if `litellm.enabled=true` and neither is set.

#### Model fallback routing

Add multiple entries for the same `model_name` to enable automatic fallback:

```yaml
litellm:
  proxy_config:
    model_list:
      - model_name: "claude-opus-4-6"
        litellm_params:
          model: "anthropic/claude-opus-4-6"
          api_key: "os.environ/ANTHROPIC_API_KEY"
      - model_name: "claude-opus-4-6"
        litellm_params:
          model: "openai/gpt-4o"
          api_key: "os.environ/OPENAI_API_KEY"
    router_settings:
      routing_strategy: "simple-shuffle"
      num_retries: 2
      timeout: 120
```

#### Verify the proxy is wired up

After install, confirm `OPENAI_API_BASE` is set on the Gateway container:

```sh
kubectl -n kubeclaw exec statefulset/kubeclaw -- env | grep OPENAI_API_BASE
# expected: OPENAI_API_BASE=http://kubeclaw-litellm:4000/v1
```

#### PostgreSQL and Redis

The upstream LiteLLM chart includes optional PostgreSQL (for virtual keys and budget tracking) and Redis (for semantic caching) subcharts. Both are off by default in this chart:

```yaml
litellm:
  db:
    deployStandalone: false   # set true to deploy PostgreSQL
  redis:
    enabled: false            # set true to deploy Redis for semantic caching
```

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

FQDN-based egress control requires a CNI with FQDN support (Cilium, Calico) or a proxy.

## Upgrade

```sh
helm upgrade my-kubeclaw kubeclaw/kubeclaw -n kubeclaw -f my-values.yaml
```

The StatefulSet uses `replicas: 1` enforced by JSON schema. The PVC persists across upgrades.

## Troubleshooting

### "unauthorized: gateway token missing" error

This error means you're accessing the Control UI without authentication. Generate a tokenized URL:

```sh
kubectl -n kubeclaw exec statefulset/my-kubeclaw -- \
  node dist/index.js dashboard --no-open
```

Use the generated URL (with token) instead of plain localhost:18789.

### Still getting unauthorized?

1. Clear browser local storage: DevTools → Application → Local Storage → delete `openclaw.control.settings.v1`
2. Restart the gateway: `kubectl -n kubeclaw rollout restart statefulset/my-kubeclaw`
3. Generate a fresh tokenized URL (tokens are tied to gateway instance)

## Uninstall

```sh
helm uninstall my-kubeclaw -n kubeclaw
# PVCs are NOT deleted by default. Delete manually if desired:
kubectl -n kubeclaw delete pvc -l app.kubernetes.io/instance=my-kubeclaw
```
