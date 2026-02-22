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
<strong>Production-grade <a href="https://openclaw.ai">OpenClaw</a> on Kubernetes.</strong><br>
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
  --set secret.data.OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)" \
  --set secret.data.OPENAI_API_KEY="sk-..." \
  --set tailscale.ssh.authKey="tskey-auth-..." \
  --set litellm.enabled=true \
  --set litellm.masterkey="sk-$(openssl rand -hex 16)"

# Wait for the pod, then open the UI
kubectl -n kubeclaw rollout status statefulset/kubeclaw
kubectl -n kubeclaw port-forward svc/kubeclaw 18789:18789
```

## What You Get

| Feature | Description |
|---------|-------------|
| **StatefulSet** | Durable PVC-backed storage at `/home/node/.openclaw` |
| **GitOps-friendly config** | Declare desired `openclaw.json`; chart handles merge or overwrite via initContainer |
| **WebSocket-ready Ingress** | Configurable TLS |
| **Split workspace volume** | Separate PVC for workspace via `persistence.splitVolumes` |
| **Chromium sidecar** | Browser automation with CDP on `127.0.0.1:9222`, never exposed |
| **LiteLLM proxy subchart** | Per-agent virtual keys, budget caps, model fallback routing, and semantic caching |
| **NetworkPolicy** | Scaffolding for locking down traffic |
| **Diagnostics CronJob** | Periodic `openclaw doctor` runs |
| **Tailscale integration** | Expose the Gateway onto your tailnet without public ingress (`tailscale.expose`), and/or SSH into the pod from any enrolled device (`tailscale.ssh`) |


## Install

### Via OCI

```sh
helm install kubeclaw oci://ghcr.io/imerica/kubeclaw \
  --version 0.1.0 \
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
| `image.tag` | `2026.2.21` | Release tag validated for this chart version |
| `image.digest` | `sha256:ce271192cd70250d16fc5911903d9953467a40faf8b34e87cbd042e6b49b6036` | Immutable digest used with the tag to prevent drift |
| `ingress.enabled` | `false` | Enable Ingress with WebSocket timeouts |
| `ingress.host` | `""` | Ingress hostname |
| `persistence.size` | `5Gi` | PVC size for Gateway state |
| `persistence.splitVolumes` | `false` | Separate PVC for workspace |
| `config.desired` | `""` | Desired `openclaw.json` (JSON5) |
| `config.mode` | `merge` | Config strategy: `merge` or `overwrite` |
| `chromium.enabled` | `false` | Chromium sidecar for CDP |
| `networkPolicy.enabled` | `false` | Enable NetworkPolicy |
| `diagnostics.enabled` | `false` | Enable diagnostics CronJob |
| `litellm.enabled` | `false` | Deploy LiteLLM proxy alongside the Gateway |
| `litellm.masterkey` | `""` | LiteLLM master key (required when enabled, must start with `sk-`) |
| `litellm.proxy_config` | *(see values.yaml)* | LiteLLM `config.yaml` contents as a YAML object |
| `tailscale.expose.enabled` | `true` | Annotate the Service for the Tailscale K8s Operator to proxy port 18789 onto your tailnet |
| `tailscale.expose.hostname` | `""` | `tailscale.com/hostname` annotation value |
| `tailscale.expose.tags` | `""` | `tailscale.com/tags` annotation value (e.g. `tag:k8s,tag:kubeclaw`) |
| `tailscale.ssh.enabled` | `true` | Add a Tailscale sidecar with `--ssh` for pod shell access from any tailnet device |
| `tailscale.ssh.authKey` | `""` | **Required when `ssh.enabled`.** Inline Tailscale auth key, unless `authKeySecretName` is set |
| `tailscale.ssh.authKeySecretName` | `""` | Existing Secret containing the auth key (alternative to `authKey`) |
| `tailscale.ssh.hostname` | `""` | Tailnet hostname for the sidecar; defaults to the Helm fullname |
| `tailscale.ssh.persistState` | `false` | Persist Tailscale state across restarts via a dedicated PVC (emptyDir when false) |

Full reference and advanced examples: [kubeclaw.ai/docs](https://kubeclaw.ai/docs)

Image pinning policy: each chart release is validated against a candidate image, then the chart defaults are updated to the exact `image.tag` + `image.digest` before publishing.

## Docs

| | |
|---|---|
| [Install Guide](docs/oss/README.md) | Step-by-step setup |
| [Verify](docs/oss/README.md#verify) | Lint, render, and schema checks |
| [Troubleshooting](docs/oss/README.md#troubleshooting) | Common issues and fixes |
| [Restore Runbook](docs/runbooks/restore.md) | Backup & recovery procedures |
| [Full Documentation](https://kubeclaw.ai/docs) | Complete reference at kubeclaw.ai |

## KubeClaw Enterprise

Need multi-tenancy, enterprise egress controls, SSO, policy-as-code, CSI-backed secrets, backup hooks, or signed OCI distribution? See [kubeclaw.ai](https://kubeclaw.ai).

## License

[Apache 2.0](LICENSE)
