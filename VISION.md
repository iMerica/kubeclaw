
# KubeClaw Vision


KubeClaw is production-grade OpenClaw on Kubernetes.
It is designed for operators who want a secure, observable, and reliable deployment path without giving up flexibility.

This document explains where the project is focused today and how we evaluate future work.

## What KubeClaw Is

KubeClaw is a Kubernetes-native Helm chart for running the OpenClaw Gateway and supporting components in real clusters.

The chart is opinionated where production defaults matter:
- secure-by-default runtime settings
- durable state and predictable upgrades
- built-in observability and diagnostics
- GitOps-friendly, declarative configuration

## Current Priorities

Priority:
- Security hardening and safe defaults
- Stability and reliability for production operations
- Setup reliability and first-run success

Next priorities:
- Better operational ergonomics for day-1/day-2 workflows
- Improved observability and diagnostics for cluster operators
- Stronger test/lint/release quality signals
- Documentation quality and contributor onboarding

## Project Principles

- Kubernetes-native first: features should work cleanly with standard cluster workflows.
- Production over novelty: reliability and clear behavior win over complexity.
- Secure by default: risky paths should be explicit and operator-controlled.
- Declarative operations: behavior should be configurable via values and manifests.
- Small, focused changes: one PR should address one issue or one topic.

## Scope and Boundaries

KubeClaw OSS aims to provide a complete, production-ready open source baseline for OpenClaw on Kubernetes.
We keep the OSS chart broadly useful and maintainable, while preserving a clear boundary between OSS and separate commercial offerings.

## Community Direction

The project succeeds when operators can:
- install with confidence
- run safely in production
- troubleshoot quickly
- contribute improvements with minimal process overhead

If a proposed change improves those outcomes, it is likely in scope.
