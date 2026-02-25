# Contributing to KubeClaw

Thanks for contributing.
This project aims to keep contribution flow straightforward and lightweight.

## Before You Start

- Open an issue for non-trivial changes to align on direction first.
- Keep one PR focused on one issue/topic.
- Prefer small, reviewable PRs over large batches.

## Local Setup

Prerequisites:
- Kubernetes 1.25+
- Helm 3.12+
- `kubectl`

Basic validation workflow:

```sh
helm lint charts/kubeclaw \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  --set litellm.masterkey=sk-test \
  --set tailscale.ssh.authKey=tskey-auth-example

helm template kubeclaw charts/kubeclaw \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=test \
  --set litellm.masterkey=sk-test \
  --set tailscale.ssh.authKey=tskey-auth-example \
  | kubectl apply --dry-run=client -f -
```

## Pull Request Expectations

- Explain why the change is needed.
- Include test/validation steps and results.
- Update docs when behavior or defaults change.
- Do not include unrelated refactors in the same PR.

## Contribution Scope

Good fits:
- reliability and operability improvements
- security hardening and safe defaults
- observability and diagnostics improvements
- docs and onboarding improvements

Out of scope for this OSS repo:
- private/commercial implementation details

## Code and Release Standards

- Preserve OpenClaw Gateway singleton behavior (`replicas: 1`).
- Keep features safe and production-oriented by default.
- Follow existing naming, labels, and templating conventions.

## Need Help?

Use:
- [SUPPORT.md](SUPPORT.md) for support channels
- [SECURITY.md](SECURITY.md) for private vulnerability reporting
