# OpenClaw OSS Chart — Install Guide

[![Chart Version](https://img.shields.io/github/v/tag/iMerica/kubeclaw?filter=v*&label=chart&color=0f7b3f)](https://github.com/iMerica/kubeclaw/releases)

## Prerequisites

- Kubernetes 1.25+
- Helm 3.12+
- A `ReadWriteOnce`-capable StorageClass (default cluster StorageClass is used if none specified)
- An OpenClaw Gateway image accessible from your cluster

## Install

### 1) One-line installer (recommended)

Fastest path for most users:

```sh
curl -fsSL https://kubeclaw.ai/install.sh | bash
```

### 2) Homebrew (installs the CLI installer)

Use Homebrew if you want the `kubeclaw` CLI for install, upgrade, diagnostics, and other workflows:

```sh
brew install iMerica/kubeclaw/kubeclaw
kubeclaw install
```

### 3) Helm chart directly (advanced Kubernetes users)

For direct Helm control:

```sh
helm install my-kubeclaw oci://ghcr.io/imerica/kubeclaw \
  --namespace kubeclaw \
  --create-namespace \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=<strong-token-here>
```

Override with a values file:

```sh
helm install my-kubeclaw oci://ghcr.io/imerica/kubeclaw \
  --namespace kubeclaw \
  --create-namespace \
  -f my-values.yaml
```

See [`../../charts/kubeclaw/values.yaml`](../../charts/kubeclaw/values.yaml) for all settings you can override.

## Verify

```sh
# Build subchart dependencies (required when litellm.enabled=true)
helm dependency build charts/kubeclaw

# Lint
helm lint charts/kubeclaw \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  --set litellm.masterkey=sk-test \
  --set tailscale.ssh.authKey=tskey-auth-example

# Dry-run render + validate
helm template kubeclaw charts/kubeclaw \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  --set litellm.masterkey=sk-test \
  --set tailscale.ssh.authKey=tskey-auth-example \
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
| `image.tag` | `2026.3.13-1` | Release tag validated for this chart version |
| `image.digest` | `sha256:ce271...` | Immutable digest used with the tag to prevent drift |
| `ingress.enabled` | `false` | Enable Ingress with WebSocket timeouts |
| `ingress.host` | `""` | Ingress hostname |
| `gatewayAPI.enabled` | `true` | Enable K8s Gateway API routing (alternative to Ingress) |
| `gatewayAPI.gatewayClassName` | `""` | GatewayClass name; auto-resolved when `controller.enabled` |
| `gatewayAPI.host` | `""` | Hostname for all HTTPRoutes. Empty = match all (local dev friendly). Set to a real domain for production. |
| `gatewayAPI.controller.enabled` | `true` | Deploy Envoy Gateway as a subchart with auto-created GatewayClass |
| `gatewayAPI.controller.gatewayClassName` | `envoy` | GatewayClass name created by the bundled controller |
| `gatewayAPI.routes.obsidian` | `/obsidian` | Path prefix for Obsidian vault HTTPRoute |
| `gatewayAPI.tls` | `{}` | TLS configuration for the Gateway listener |
| `gatewayAPI.annotations` | `{}` | Extra annotations on the Gateway resource |
| `gatewayAPI.crds.install` | `false` | Install Gateway API CRDs via hook Job (BYO-controller setups) |
| `persistence.size` | `5Gi` | PVC size for Gateway state |
| `persistence.splitVolumes` | `false` | Separate PVC for workspace |
| `persistence.fixPermissions.enabled` | `true` | Normalize state directory ownership on startup |
| `config.desired` | `""` | Desired `openclaw.json` (JSON5) |
| `config.mode` | `merge` | Config strategy: `merge` or `overwrite` |
| `nodeOptions` | `"--max-old-space-size=1536"` | `NODE_OPTIONS` passed to the Gateway container |
| `extraEnv` | `[]` | Extra env vars injected into the Gateway container |
| `tools.enabled` | `true` | Enable reusable `tools-init` CLI installer |
| `tools.clis.github.enabled` | `true` | Install GitHub CLI (`gh`) in the Gateway pod |
| `tools.clis.jira.enabled` | `true` | Install JIRA CLI in the Gateway pod |
| `tools.clis.linear.enabled` | `true` | Install Linear CLI in the Gateway pod |
| `tools.clis.asana.enabled` | `true` | Install Asana CLI in the Gateway pod |
| `tools.clis.trello.enabled` | `true` | Install Trello CLI in the Gateway pod |
| `github.enabled` | `true` | Enable GitHub integration wiring (soft-enabled if token not set) |
| `github.auth.token` | `""` | Optional GitHub token (merged as `GH_TOKEN` + `GITHUB_TOKEN`) |
| `jira.enabled` | `true` | Enable JIRA integration (soft-enabled if token not set) |
| `jira.auth.token` | `""` | Optional JIRA API token (merged as `JIRA_API_TOKEN`) |
| `linear.enabled` | `true` | Enable Linear integration (soft-enabled if token not set) |
| `linear.auth.token` | `""` | Optional Linear API key (merged as `LINEAR_API_KEY`) |
| `asana.enabled` | `true` | Enable Asana integration (soft-enabled if token not set) |
| `asana.auth.token` | `""` | Optional Asana PAT (merged as `ASANA_PAT`) |
| `trello.enabled` | `true` | Enable Trello integration (soft-enabled if token not set) |
| `trello.auth.apiKey` | `""` | Optional Trello API key (merged as `TRELLO_API_KEY`) |
| `trello.auth.token` | `""` | Optional Trello token (merged as `TRELLO_TOKEN`) |
| `skillStacks.enabled` | `true` | Enable domain-curated SkillStack collections |
| `skillStacks.platformEngineering.enabled` | `true` | Platform engineering skill stack |
| `skillStacks.devops.enabled` | `true` | DevOps skill stack |
| `skillStacks.sre.enabled` | `true` | SRE skill stack |
| `skillStacks.swe.enabled` | `true` | SWE skill stack |
| `skillStacks.qa.enabled` | `true` | QA skill stack |
| `skillStacks.marketing.enabled` | `true` | Marketing skill stack |
| `obsidian.enabled` | `true` | PVC-backed markdown vault at `/vaults/obsidian` |
| `obsidian.persistence.size` | `5Gi` | Obsidian vault PVC size |
| `memory.enabled` | `true` | QMD hybrid search (BM25 + vectors + reranking) for memory |
| `memory.image.repository` | `oven/bun` | Bun image for QMD init and CronJob pods |
| `memory.image.tag` | `1.2-alpine` | Bun image tag |
| `memory.qmd.packageUrl` | `@tobilu/qmd` | QMD package source for Bun global install |
| `memory.update.schedule` | `*/5 * * * *` | CronJob schedule for BM25 re-indexing |
| `memory.embed.schedule` | `*/15 * * * *` | CronJob schedule for vector embedding generation |
| `chromium.enabled` | `true` | Chromium Deployment + ClusterIP Service for CDP |
| `egressFilter.enabled` | `true` | Deploy Blocky DNS proxy for egress filtering |
| `egressFilter.blockCountries` | `[RU, CN]` | Country TLDs to block via regex |
| `egressFilter.denylists` | *(threats + malware)* | Named blocklist groups with URLs fetched by Blocky |
| `egressFilter.allowlists` | `[]` | Domains that are never blocked (overrides denylists) |
| `networkPolicy.enabled` | `true` | Enable NetworkPolicy |
| `networkPolicy.egress.allowAll` | `false` | Allow all egress; when false, egress is deny-all with explicit allowlists |
| `backup.enabled` | `false` | Enable S3 backup CronJob (requires S3 credentials in `secret.data`) |
| `backup.schedule` | `0 2 * * *` | Cron schedule for backups (default: daily at 2am UTC) |
| `backup.pathPrefix` | `""` | S3 path prefix; defaults to `<namespace>/<release>` |
| `backup.onDelete.enabled` | `true` | Run a final backup before `helm uninstall` |
| `diagnostics.enabled` | `true` | Enable diagnostics CronJob |
| `observability.enabled` | `true` | Deploy ClickStack (ClickHouse + HyperDX + OTel) and KubeClaw OTel collectors |
| `observability.gateway.enabled` | `true` | Inject OTEL env vars into Gateway for trace/log export |
| `observability.nodeCollector.enabled` | `true` | DaemonSet collecting pod logs and host metrics |
| `observability.clusterCollector.enabled` | `true` | Deployment collecting K8s events and cluster metrics |
| `observability.ingress.enabled` | `true` | Expose HyperDX UI via Ingress |
| `litellm.enabled` | `true` | Deploy LiteLLM proxy alongside the Gateway |
| `litellm.masterkey` | `""` | LiteLLM master key (must start with `sk-`) |
| `litellm.redis.enabled` | `true` | Deploy Redis for semantic caching |
| `litellm.proxy_config` | *(see values.yaml)* | LiteLLM `config.yaml` contents as YAML object |
| `tailscale.expose.enabled` | `true` | Annotate Service for Tailscale K8s Operator |
| `tailscale.expose.hostname` | `""` | `tailscale.com/hostname` annotation value |
| `tailscale.expose.tags` | `""` | `tailscale.com/tags` annotation value |
| `tailscale.ssh.enabled` | `true` | Tailscale sidecar with `--ssh` for pod shell access |
| `tailscale.ssh.authKey` | `""` | **Required when `ssh.enabled`.** Inline Tailscale auth key |
| `tailscale.ssh.authKeySecretName` | `""` | Existing Secret with auth key (alternative to `authKey`) |
| `tailscale.ssh.hostname` | `""` | Tailnet hostname; defaults to Helm fullname |
| `tailscale.ssh.persistState` | `false` | Persist Tailscale state via dedicated PVC |
| `pod.runtimeClassName` | `""` | RuntimeClass for exec isolation (gVisor, Kata) |
| `pod.annotations` | `{}` | Extra annotations for the Gateway pod |
| `pod.labels` | `{}` | Extra labels for the Gateway pod |
| `pod.nodeSelector` | `{}` | Node selector for the Gateway pod |
| `pod.tolerations` | `[]` | Tolerations for the Gateway pod |
| `pod.affinity` | `{}` | Affinity rules for the Gateway pod |
| `serviceAccount.create` | `true` | Create a ServiceAccount for the Gateway |
| `serviceAccount.name` | `""` | Override ServiceAccount name |
| `serviceAccount.annotations` | `{}` | Annotations on the ServiceAccount |

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
| Obsidian Vault | `http://127.0.0.1/obsidian/` |

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
    obsidian: /obsidian
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

### Skills, Tools, and Integrations

The chart ships with:

- **SkillStacks**: domain-curated skill collections (platform engineering, DevOps, SRE, SWE, QA, marketing) installed at deploy time
- **Tools-init**: reusable CLI provisioning via initContainer
- **CLIs**: `gh`, `jira`, `linear`, `asana`, and `trello` installed by default

#### GitHub

```yaml
github:
  enabled: true
  auth:
    token: ghp_your_token_here  # merged as GH_TOKEN + GITHUB_TOKEN
```

#### JIRA

```yaml
jira:
  enabled: true
  auth:
    token: your_jira_api_token  # merged as JIRA_API_TOKEN
```

#### Linear

```yaml
linear:
  enabled: true
  auth:
    token: your_linear_api_key  # merged as LINEAR_API_KEY
```

#### Asana

```yaml
asana:
  enabled: true
  auth:
    token: your_asana_pat  # merged as ASANA_PAT
```

#### Trello

```yaml
trello:
  enabled: true
  auth:
    apiKey: your_trello_api_key  # merged as TRELLO_API_KEY
    token: your_trello_token     # merged as TRELLO_TOKEN
```

All integrations are soft-enabled by default. If no token is configured, install still succeeds but authenticated operations remain unavailable. Users who bring their own Secret via `secret.existingSecretName` should include the relevant keys there.

After deploy, verify any CLI:

```sh
kubectl -n kubeclaw exec statefulset/kubeclaw-gateway -c gateway -- gh --version
kubectl -n kubeclaw exec statefulset/kubeclaw-gateway -c gateway -- jira version
```

For workflow ideas (webhook-driven PR review, inline comments, summary recommendations), see the OpenClaw cookbook: [Code Review Bot](https://openclawdoc.com/docs/cookbook/code-review-bot/).

### Chromium Deployment

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

### Memory (QMD)

The chart deploys [QMD](https://docs.openclaw.ai/reference/memory-config#qmd-backend-experimental), a local-first hybrid search engine that combines BM25 keyword matching with vector similarity and MMR reranking. QMD is installed as a CLI via a dedicated initContainer using the `oven/bun` image. The Gateway shells out to `qmd` for all `memory_search` operations.

**What you get out of the box:**

- Hybrid search (BM25 + vector) with configurable weighting (default: 70% semantic, 30% keyword)
- MMR reranking for relevance/diversity balance
- Temporal decay with 30-day half-life (evergreen files like `MEMORY.md` are exempt)
- Two CronJobs for K8s-native observability:
  - `qmd update` (every 5 min): re-indexes markdown files into the BM25 search index
  - `qmd embed` (every 15 min): generates vector embeddings via node-llama-cpp with a local GGUF model

QMD state (SQLite DB + embeddings + cached GGUF model) is stored on the Gateway's existing PVC under `~/.openclaw/agents/<agentId>/qmd/`. No additional PVC is needed.

> **First run note**: The first `qmd embed` CronJob run downloads a ~0.6 GB GGUF embedding model. This is cached on the PVC for subsequent runs.

#### Customize

```yaml
memory:
  enabled: true
  update:
    schedule: "*/10 * * * *"   # less frequent re-indexing
  embed:
    schedule: "0 * * * *"      # hourly embedding
    resources:
      limits:
        cpu: "4"               # more CPU for faster embedding
        memory: 4Gi
```

#### Disable

```yaml
memory:
  enabled: false
```

When disabled, no QMD resources are created. The Gateway falls back to its built-in SQLite memory backend.

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

The upstream LiteLLM chart includes optional PostgreSQL (for virtual keys and budget tracking) and Redis (for semantic caching) subcharts. Redis is enabled by default for semantic caching; PostgreSQL is off:

```yaml
litellm:
  db:
    deployStandalone: false   # set true to deploy PostgreSQL
  redis:
    enabled: true             # semantic caching enabled by default
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
kubectl -n kubeclaw exec -it statefulset/kubeclaw-gateway -c gateway -- node dist/index.js status
kubectl -n kubeclaw exec -it statefulset/kubeclaw-gateway -c gateway -- node dist/index.js gateway status
kubectl -n kubeclaw exec -it statefulset/kubeclaw-gateway -c gateway -- node dist/index.js doctor
kubectl -n kubeclaw exec -it statefulset/kubeclaw-gateway -c gateway -- node dist/index.js channels status --probe
```

### Enable diagnostics CronJob

```yaml
diagnostics:
  enabled: true
  schedule: "0 * * * *"
```

Output is written to pod logs. Pipe to your logging stack.

## S3 Backup

Back up the Gateway state directory to any S3-compatible storage (AWS S3, MinIO, Backblaze B2, Cloudflare R2, etc.) on a cron schedule. A pre-delete hook also runs a final backup before `helm uninstall`, so state is preserved even when tearing down the release.

Backups use [rclone](https://rclone.org/) to copy the flat Markdown files. No database dump or special tooling is needed.

### Enable

Add S3 credentials to `secret.data` and enable the backup:

```yaml
secret:
  create: true
  data:
    OPENCLAW_GATEWAY_TOKEN: "your-token"
    S3_ENDPOINT: "https://s3.us-east-1.amazonaws.com"
    S3_BUCKET: "my-kubeclaw-backups"
    S3_ACCESS_KEY_ID: "AKIAEXAMPLE"
    S3_SECRET_ACCESS_KEY: "your-secret-key"
    S3_REGION: "us-east-1"  # optional

backup:
  enabled: true
  schedule: "0 2 * * *"   # daily at 2am UTC
```

The chart validates that `S3_BUCKET`, `S3_ACCESS_KEY_ID`, and `S3_SECRET_ACCESS_KEY` are present in `secret.data` when `backup.enabled` is true.

### S3 path layout

Scheduled backups are timestamped. The pre-delete backup overwrites a single `pre-delete/` prefix so only the latest snapshot is kept:

```
s3://my-kubeclaw-backups/
  <namespace>/<release>/
    2026-03-07T02-00-00Z/       # scheduled
    2026-03-08T02-00-00Z/       # scheduled
    pre-delete/                  # latest pre-delete snapshot
```

Override the `<namespace>/<release>` prefix with `backup.pathPrefix`.

### Non-AWS providers

Any S3-compatible endpoint works. Set `S3_ENDPOINT` to your provider's URL:

| Provider | `S3_ENDPOINT` example |
|----------|----------------------|
| MinIO | `http://minio.minio.svc:9000` |
| Backblaze B2 | `https://s3.us-west-004.backblazeb2.com` |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |

### Disable the pre-delete hook

If you do not want a backup on `helm uninstall`:

```yaml
backup:
  enabled: true
  onDelete:
    enabled: false
```

### Restoring from an S3 backup

See the [Restore Runbook](../runbooks/restore.md) for step-by-step instructions on restoring from S3.

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

NetworkPolicy is enabled by default with egress deny-all (`egress.allowAll: false`). Inbound traffic is restricted to the Ingress controller namespace:

```yaml
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    kubernetes.io/metadata.name: ingress-nginx
  egress:
    allowAll: false  # deny-all egress by default
```

To allow all egress (for clusters without a NetworkPolicy-capable CNI), set `egress.allowAll: true`. FQDN-based egress control requires a CNI with FQDN support (Cilium, Calico) or a proxy.

## Upgrade

```sh
helm upgrade my-kubeclaw kubeclaw/kubeclaw -n kubeclaw -f my-values.yaml
```

The StatefulSet uses `replicas: 1` enforced by JSON schema. The PVC persists across upgrades.

## Troubleshooting

### `kubeclaw update` appears to hang during upgrade

Recent CLI versions add a hard timeout around Helm operations so upgrades fail fast instead of hanging indefinitely.

```sh
# update CLI (Homebrew)
brew upgrade iMerica/kubeclaw/kubeclaw

# then retry
kubeclaw update
```

If you still hit a timeout, run Helm directly to inspect rollout blockers:

```sh
helm upgrade my-kubeclaw oci://ghcr.io/imerica/kubeclaw \
  -n kubeclaw \
  --reuse-values \
  --wait --timeout 10m
```

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
