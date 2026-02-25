#!/usr/bin/env bash
# Add all non-OCI Helm chart repositories required by the kubeclaw chart.
# OCI dependencies (litellm-helm, gateway-helm) are resolved automatically.
set -euo pipefail

helm repo add clickstack https://clickhouse.github.io/ClickStack-helm-charts
helm repo update
