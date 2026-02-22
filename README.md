<div align="center">
<pre>
██╗  ██╗██╗   ██╗██████╗ ███████╗ ██████╗██╗      █████╗ ██╗    ██╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔════╝██║     ██╔══██╗██║    ██║
█████╔╝ ██║   ██║██████╔╝█████╗  ██║     ██║     ███████║██║ █╗ ██║
██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██║     ██║     ██╔══██║██║███╗██║
██║  ██╗╚██████╔╝██████╔╝███████╗╚██████╗███████╗██║  ██║╚███╔███╔╝
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
</pre>
</div>

<p align="center">
<strong>The Helm chart for running <a href="https://openclaw.dev">OpenClaw</a> on Kubernetes.</strong><br>
<sub>Stateful. Single-replica. Production-ready.</sub>
</p>

<p align="center">
<a href="https://github.com/iMerica/kubeclaw/actions/workflows/lint-test.yaml"><img src="https://github.com/iMerica/kubeclaw/actions/workflows/lint-test.yaml/badge.svg?branch=master" alt="CI"></a>
<a href="https://github.com/iMerica/kubeclaw/releases"><img src="https://img.shields.io/github/v/release/iMerica/kubeclaw?label=chart&color=0f7b3f" alt="Chart Version"></a>
<a href="https://kubernetes.io/releases/"><img src="https://img.shields.io/badge/k8s-1.25%2B-326ce5?logo=kubernetes&logoColor=white" alt="Kubernetes 1.25+"></a>
<a href="https://helm.sh"><img src="https://img.shields.io/badge/Helm-3.12%2B-0f1689?logo=helm&logoColor=white" alt="Helm 3.12+"></a>
<a href="https://github.com/iMerica/kubeclaw/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-Apache_2.0-blue" alt="License"></a>
<a href="https://ghcr.io/imerica/kubeclaw"><img src="https://img.shields.io/badge/OCI-ghcr.io-purple?logo=github" alt="OCI Registry"></a>
<a href="https://github.com/aquasecurity/trivy"><img src="https://img.shields.io/badge/Trivy-scanned-1904DA?logo=aquasec&logoColor=white" alt="Trivy"></a>
<a href="https://github.com/yannh/kubeconform"><img src="https://img.shields.io/badge/kubeconform-validated-4CAF50" alt="kubeconform"></a>
<a href="https://github.com/stackrox/kube-linter"><img src="https://img.shields.io/badge/kube--linter-passing-ee0000" alt="kube-linter"></a>
</p>

---

## Quick Start

```sh
helm install kubeclaw oci://ghcr.io/imerica/kubeclaw \
  --namespace kubeclaw --create-namespace \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
```

That's it. One Gateway, one PVC, one Secret, running.

## What You Get

- **StatefulSet** with durable PVC-backed storage at `/home/node/.openclaw`
- **WebSocket-ready Ingress** with configurable TLS
- **Health probes** (startup, liveness, readiness) baked in
- **GitOps-friendly config**: declare desired `openclaw.json` and the chart handles merge or overwrite via initContainer
- **Optional Chromium sidecar** for browser automation (CDP on `127.0.0.1:9222`, never exposed)
- **NetworkPolicy** scaffolding for locking down traffic
- **Diagnostics CronJob** for periodic `openclaw doctor` runs
- **Replica enforcement**: JSON Schema rejects `replicas != 1` at install time (the Gateway is stateful; this is intentional)

## Install

### Via OCI (recommended)

```sh
helm install kubeclaw oci://ghcr.io/imerica/kubeclaw \
  --version 0.1.0 \
  --namespace kubeclaw \
  --create-namespace \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=change-me
```

### Via Helm Repo

```sh
helm repo add kubeclaw https://iMerica.github.io/kubeclaw
helm repo update

helm install kubeclaw kubeclaw/kubeclaw \
  --namespace kubeclaw \
  --create-namespace \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=change-me
```

## Configuration

All values are documented inline in [`charts/kubeclaw/values.yaml`](charts/kubeclaw/values.yaml).

| Key | Default | Description |
|-----|---------|-------------|
| `secret.data.OPENCLAW_GATEWAY_TOKEN` | *none* | **Required.** Gateway auth token |
| `image.repository` | `ghcr.io/openclaw/openclaw` | Gateway container image |
| `image.tag` | `latest` | Image tag (pin in production) |
| `ingress.enabled` | `false` | Enable Ingress with WebSocket timeouts |
| `ingress.host` | `""` | Ingress hostname |
| `persistence.size` | `5Gi` | PVC size for Gateway state |
| `persistence.splitVolumes` | `false` | Separate PVC for workspace |
| `config.desired` | `""` | Desired `openclaw.json` (JSON5) |
| `config.mode` | `merge` | Config strategy: `merge` or `overwrite` |
| `chromium.enabled` | `false` | Chromium sidecar for CDP |
| `networkPolicy.enabled` | `false` | Enable NetworkPolicy |
| `diagnostics.enabled` | `false` | Enable diagnostics CronJob |

Full reference and advanced examples: [kubeclaw.ai/docs](https://kubeclaw.ai/docs)

## Verify

```sh
# Lint
helm lint charts/kubeclaw

# Dry-run
helm template kubeclaw charts/kubeclaw \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  | kubectl apply --dry-run=client -f -

# Confirm replica enforcement (must error)
helm template kubeclaw charts/kubeclaw --set replicaCount=2
```

## Docs

| | |
|---|---|
| [Install Guide](docs/oss/README.md) | Step-by-step setup |
| [Restore Runbook](docs/runbooks/restore.md) | Backup & recovery procedures |
| [Full Documentation](https://kubeclaw.ai/docs) | Complete reference at kubeclaw.ai |

## KubeClaw Enterprise

Need multi-tenancy, enterprise egress controls, SSO, policy-as-code, CSI-backed secrets, backup hooks, or signed OCI distribution? See [kubeclaw.ai](https://kubeclaw.ai).

## License

[Apache 2.0](LICENSE)
