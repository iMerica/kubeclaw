# OpenClaw OSS Chart — Install Guide

[![Chart Version](https://img.shields.io/github/v/tag/iMerica/kubeclaw?filter=v*&label=chart&color=0f7b3f)](https://github.com/iMerica/kubeclaw/releases)

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

The Gateway Service is `ClusterIP` by default, so it is not reachable outside the cluster without port-forwarding, Ingress, or Gateway API routing.

### Using `install.sh` (recommended for local dev)

`scripts/install.sh` automatically starts a background port-forward after install and prints an authenticated dashboard URL rewritten to `localhost`:

```sh
./scripts/install.sh
# ...
# Port-forward running (PID 12345). Stop with: kill 12345
# Open in your browser: http://localhost:18789/?token=...
```

Override the local port with `LOCAL_PORT=8080 ./scripts/install.sh`.

### Manual port-forward

```sh
kubectl port-forward -n kubeclaw svc/kubeclaw-gateway 18789:18789 &
```

Then generate an authenticated URL:

```sh
kubectl -n kubeclaw exec statefulset/kubeclaw-gateway -c gateway -- \
  node dist/index.js dashboard --no-open
```

The output contains a `Dashboard URL` with a token query parameter. Replace the host portion with `localhost:18789` (or whichever local port you forwarded to). Opening without the token shows "unauthorized" errors.

### Production access

For access beyond `localhost`, configure one of:

- **K8s Gateway API** (default, `gatewayAPI.enabled: true`): see [K8s Gateway API Routing](#k8s-gateway-api-routing) below
- **Ingress** (`ingress.enabled: true`): see [Enabling Ingress](#enabling-ingress) below
- **Tailscale** (`tailscale.expose.enabled: true`): exposes the service on your tailnet without any public endpoint

## Configuration Reference

See [`values.yaml`](../../charts/kubeclaw/values.yaml) for all options with inline documentation.

### Minimum required values

| Key | Required | Notes |
|-----|----------|-------|
| `secret.data.OPENCLAW_GATEWAY_TOKEN` | Yes | Strong random string. Treat as a password. |
| `tailscale.ssh.authKey` | Yes (unless `authKeySecretName` set) | Tailscale auth key for SSH sidecar |
| `litellm.masterkey` | Yes (when `litellm.enabled`) | Must start with `sk-` |
| `image.repository` | Yes | Gateway container image repository |
| `image.tag` | Yes | Pin to a specific tag in production |

### All values

| Key | Default | Description |
|-----|---------|-------------|
| `secret.data.OPENCLAW_GATEWAY_TOKEN` | *none* | **Required.** Gateway auth token |
| `image.repository` | `ghcr.io/openclaw/openclaw` | Gateway container image |
| `image.tag` | `2026.2.21` | Release tag validated for this chart version |
| `image.digest` | `sha256:ce271...` | Immutable digest used with the tag to prevent drift |
| `ingress.enabled` | `false` | Enable Ingress with WebSocket timeouts |
| `ingress.host` | `""` | Ingress hostname |
| `gatewayAPI.enabled` | `true` | Enable K8s Gateway API routing (alternative to Ingress) |
| `gatewayAPI.gatewayClassName` | `""` | GatewayClass name; auto-resolved when `controller.enabled` |
| `gatewayAPI.host` | `""` | Hostname for all HTTPRoutes. Empty = match all (local dev friendly). Set to a real domain for production. |
| `gatewayAPI.controller.enabled` | `true` | Deploy Envoy Gateway as a subchart with auto-created GatewayClass |
| `gatewayAPI.controller.gatewayClassName` | `envoy` | GatewayClass name created by the bundled controller |
| `gatewayAPI.crds.install` | `false` | Install Gateway API CRDs via hook Job (BYO-controller setups) |
| `persistence.size` | `5Gi` | PVC size for Gateway state |
| `persistence.splitVolumes` | `false` | Separate PVC for workspace |
| `config.desired` | `""` | Desired `openclaw.json` (JSON5) |
| `config.mode` | `merge` | Config strategy: `merge` or `overwrite` |
| `tools.enabled` | `true` | Enable reusable `tools-init` CLI installer |
| `tools.clis.github.enabled` | `true` | Install GitHub CLI (`gh`) in the Gateway pod |
| `github.enabled` | `true` | Enable GitHub integration wiring (soft-enabled if token not set) |
| `github.auth.token` | `""` | Optional GitHub token for authenticated `gh` + GitHub skill actions |
| `chromium.enabled` | `true` | Chromium Deployment + ClusterIP Service for CDP |
| `egressFilter.enabled` | `true` | Deploy Blocky DNS proxy for egress filtering |
| `egressFilter.blockCountries` | `[RU, CN]` | Country TLDs to block via regex |
| `egressFilter.denylists` | *(threats + malware)* | Named blocklist groups with URLs fetched by Blocky |
| `egressFilter.allowlists` | `[]` | Domains that are never blocked (overrides denylists) |
| `networkPolicy.enabled` | `false` | Enable NetworkPolicy |
| `diagnostics.enabled` | `true` | Enable diagnostics CronJob |
| `observability.enabled` | `true` | Deploy ClickStack (ClickHouse + HyperDX + OTel) and KubeClaw OTel collectors |
| `observability.gateway.enabled` | `true` | Inject OTEL env vars into Gateway for trace/log export |
| `observability.nodeCollector.enabled` | `true` | DaemonSet collecting pod logs and host metrics |
| `observability.clusterCollector.enabled` | `true` | Deployment collecting K8s events and cluster metrics |
| `observability.ingress.enabled` | `true` | Expose HyperDX UI via Ingress |
| `litellm.enabled` | `true` | Deploy LiteLLM proxy alongside the Gateway |
| `litellm.masterkey` | `""` | LiteLLM master key (must start with `sk-`) |
| `litellm.proxy_config` | *(see values.yaml)* | LiteLLM `config.yaml` contents as YAML object |
| `tailscale.expose.enabled` | `true` | Annotate Service for Tailscale K8s Operator |
| `tailscale.expose.hostname` | `""` | `tailscale.com/hostname` annotation value |
| `tailscale.expose.tags` | `""` | `tailscale.com/tags` annotation value |
| `tailscale.ssh.enabled` | `true` | Tailscale sidecar with `--ssh` for pod shell access |
| `tailscale.ssh.authKey` | `""` | **Required when `ssh.enabled`.** Inline Tailscale auth key |
| `tailscale.ssh.authKeySecretName` | `""` | Existing Secret with auth key (alternative to `authKey`) |
| `tailscale.ssh.hostname` | `""` | Tailnet hostname; defaults to Helm fullname |
| `tailscale.ssh.persistState` | `false` | Persist Tailscale state via dedicated PVC |

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

### K8s Gateway API Routing

The chart supports [Gateway API](https://gateway-api.sigs.k8s.io/) (`gateway.networking.k8s.io/v1`) as an alternative to Ingress, providing single-hostname path-based routing for all KubeClaw services.

> **Naming note**: "Gateway API" refers to the Kubernetes routing standard. "OpenClaw Gateway" refers to the application StatefulSet.

#### Path A — Bundled controller (local / simple clusters)

One command, no prerequisites. The chart deploys Envoy Gateway as a subchart and creates a GatewayClass automatically:

```sh
helm install kubeclaw charts/kubeclaw \
  --namespace kubeclaw --create-namespace \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --set litellm.masterkey="sk-$(openssl rand -hex 16)" \
  --set tailscale.ssh.authKey="tskey-auth-..."
```

This deploys Envoy Gateway, creates a `GatewayClass` named `envoy`, and wires up all HTTPRoutes. No manual CRD or controller installation required. With the default empty `gatewayAPI.host`, routes match any hostname — `http://127.0.0.1/` works immediately for local dev. Set `gatewayAPI.host` to a real domain for production.

#### Path B — BYO controller (Istio, Cilium, etc.)

If your cluster already has a Gateway API controller, just point to its GatewayClass:

```sh
helm install kubeclaw charts/kubeclaw \
  --namespace kubeclaw --create-namespace \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --set litellm.masterkey="sk-$(openssl rand -hex 16)" \
  --set tailscale.ssh.authKey="tskey-auth-..." \
  --set gatewayAPI.enabled=true \
  --set gatewayAPI.gatewayClassName=istio \
  --set gatewayAPI.host=kubeclaw.example.com
```

If your cluster doesn't have Gateway API CRDs installed, add `--set gatewayAPI.crds.install=true` to install them via a pre-install hook Job.

#### Accessing the services

The Gateway API controller creates a data-plane Service. On Docker Desktop this gets `localhost`; on kind/k3d you may need to port-forward:

```sh
# Find the Envoy data-plane Service
ENVOY_SVC=$(kubectl get svc -A -l gateway.networking.k8s.io/gateway-name=kubeclaw-gateway-api \
  -o jsonpath='{.items[0].metadata.namespace}/{.items[0].metadata.name}')

# If LoadBalancer is pending (kind/k3d), port-forward to it:
kubectl port-forward -n "${ENVOY_SVC%%/*}" "svc/${ENVOY_SVC##*/}" 8080:80
```

With the default empty `gatewayAPI.host`, no `/etc/hosts` entry is needed — routes match any hostname:

| Service | URL |
|---------|-----|
| OpenClaw Gateway (Canvas UI) | `http://127.0.0.1/#token=YOUR_TOKEN` |
| HyperDX (Observability) | `http://127.0.0.1/o11y/` |
| LiteLLM (Proxy Dashboard) | `http://127.0.0.1/litellm/` |
| Egress Filter (Blocky API) | `http://127.0.0.1/filtering/` |

Replace `127.0.0.1` with `127.0.0.1:8080` if using port-forward instead of a working LoadBalancer.

> **Note**: The OpenClaw Gateway UI requires a token. Pass it via the URL fragment (`#token=...`) or paste it in Control UI settings. Find it with:
> ```sh
> kubectl -n kubeclaw get secret kubeclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d
> ```

#### Route customization

Override the default path prefixes in `values.yaml`:

```yaml
gatewayAPI:
  enabled: true
  gatewayClassName: envoy   # or omit when controller.enabled=true
  host: ""                  # empty = match all; set a domain for production
  routes:
    openclaw: /
    o11y: /o11y
    litellm: /litellm
    filtering: /filtering
```

Subpath routes (`/o11y`, `/litellm`, `/filtering`) automatically strip the prefix before forwarding to the backend, so the services see requests as if they were routed to `/`.

### Desired Config (GitOps)

Mount an `openclaw.json` (JSON5) config via ConfigMap, applied at pod start:

```yaml
config:
  desired: |
    {
      "gateway": { "bind": "lan" },
      "tools": { "exec": { "enabled": true } }
    }
  mode: merge  # or "overwrite"
```

- `merge`: applies JSON merge-patch onto the existing config (preserves runtime edits)
- `overwrite`: replaces the entire config file

A config change triggers a rolling restart (checksum annotation in pod template).

### Skills, Tools, and GitHub PR Automation

The chart now ships with:

- default `github` skill installation (`skills.list`)
- reusable `tools-init` CLI provisioning
- `gh` CLI installed by default (`tools.clis.github.enabled=true`)

To enable authenticated PR/issue workflows, set a GitHub token:

```yaml
github:
  enabled: true
  auth:
    token: ghp_your_token_here
```

The token is merged into the main Secret as `GH_TOKEN` and `GITHUB_TOKEN`. Users who bring their own Secret via `secret.existingSecretName` should include these keys there.

After deploy:

```sh
kubectl -n kubeclaw exec statefulset/my-kubeclaw-gateway-0 -c gateway -- gh --version
kubectl -n kubeclaw exec statefulset/my-kubeclaw-gateway-0 -c gateway -- gh auth status
```

If no token is configured, install still succeeds (soft-enabled), but authenticated GitHub operations will fail until credentials are provided.

For workflow ideas (webhook-driven PR review, inline comments, summary recommendations), see the OpenClaw cookbook: [Code Review Bot](https://openclawdoc.com/docs/cookbook/code-review-bot/).

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

The `masterkey` value is required when `litellm.enabled=true` and is enforced by the chart's JSON schema. It is merged into the main Secret as `LITELLM_API_KEY`.

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
