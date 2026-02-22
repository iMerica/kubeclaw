#!/usr/bin/env bash
#
# Installs (or upgrades) the kubeclaw Helm chart.
# Just run: ./scripts/install.sh
#
# All variables have defaults below — edit them in-place for your environment.
# Any variable can also be overridden via environment:
#   NAMESPACE=prod ./scripts/install.sh
#
set -euo pipefail

# --- Configuration (edit these or override via environment) -----------------
RELEASE="${RELEASE:-kubeclaw}"
NAMESPACE="${NAMESPACE:-kubeclaw}"

# Gateway auth token (secret.data.OPENCLAW_GATEWAY_TOKEN)
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"

# LiteLLM proxy master key — must start with "sk-" (required when litellm is enabled)
LITELLM_MASTERKEY="${LITELLM_MASTERKEY:-sk-changeme}"

# Provider API keys — passed to both the Gateway and LiteLLM proxy
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Optional: path to a custom values file layered on top of chart defaults
VALUES_FILE="${VALUES_FILE:-}"
# ----------------------------------------------------------------------------

CHART_DIR="$(cd "$(dirname "$0")/../charts/kubeclaw" && pwd)"

# --- Preflight checks ---
for cmd in helm kubectl; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is required but not found in PATH." >&2
    exit 1
  fi
done

# --- Ensure namespace exists ---
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo ">>> Creating namespace '${NAMESPACE}'..."
  kubectl create namespace "${NAMESPACE}"
fi

# --- Build helm args ---
HELM_ARGS=(
  upgrade --install "${RELEASE}" "${CHART_DIR}"
  --namespace "${NAMESPACE}"
  --set "secret.create=true"
  --set "secret.data.OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
  --set "litellm.masterkey=${LITELLM_MASTERKEY}"
  --set "secret.data.OPENAI_API_KEY=${OPENAI_API_KEY}"
  --wait
  --timeout 5m
)

if [[ -n "${VALUES_FILE}" ]]; then
  if [[ ! -f "${VALUES_FILE}" ]]; then
    echo "ERROR: VALUES_FILE '${VALUES_FILE}' does not exist." >&2
    exit 1
  fi
  HELM_ARGS+=(--values "${VALUES_FILE}")
fi

# --- Update Helm dependencies ---
echo "=== KubeClaw Install ==="
echo "Release:   ${RELEASE}"
echo "Namespace: ${NAMESPACE}"
echo "Chart:     ${CHART_DIR}"
echo ""

echo ">>> Updating chart dependencies..."
helm dependency update "${CHART_DIR}" --skip-refresh 2>/dev/null || helm dependency build "${CHART_DIR}"

# --- Install / upgrade ---
echo ">>> Installing/upgrading release '${RELEASE}'..."
helm "${HELM_ARGS[@]}"

echo ""
echo "=== Installed successfully ==="
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE}"

# --- Print dashboard URL ---
echo ""
URL=$(kubectl -n "${NAMESPACE}" exec "statefulset/${RELEASE}" -- \
  node dist/index.js dashboard --no-open 2>/dev/null | grep "Dashboard URL:" || true)
if [[ -n "${URL}" ]]; then
  echo "Open this URL in your browser: ${URL#*Dashboard URL: }"
fi
