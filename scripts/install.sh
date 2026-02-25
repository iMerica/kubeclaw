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

# Tailscale auth key — required when tailscale.ssh.enabled=true (the default).
# Accepts either TS_AUTHKEY or TAILSCALE_AUTH_KEY from the environment.
TS_AUTHKEY="${TS_AUTHKEY:-${TAILSCALE_AUTH_KEY:-}}"

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
if [[ -z "${TS_AUTHKEY}" ]]; then
  echo "ERROR: A Tailscale auth key is required (tailscale.ssh is enabled by default)." >&2
  echo "  Set TAILSCALE_AUTH_KEY or TS_AUTHKEY in your environment, or pass a VALUES_FILE" >&2
  echo "  with tailscale.ssh.authKeySecretName pointing to an existing Secret." >&2
  exit 1
fi

HELM_ARGS=(
  upgrade --install "${RELEASE}" "${CHART_DIR}"
  --namespace "${NAMESPACE}"
  --set "secret.create=true"
  --set "secret.data.OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
  --set "litellm.masterkey=${LITELLM_MASTERKEY}"
  --set "secret.data.OPENAI_API_KEY=${OPENAI_API_KEY}"
  --set "tailscale.ssh.authKey=${TS_AUTHKEY}"
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
echo "Tailscale: ${TS_AUTHKEY:0:12}***"
echo ""

echo ">>> Updating chart dependencies..."
helm dependency update "${CHART_DIR}" --skip-refresh 2>/dev/null || helm dependency build "${CHART_DIR}"

# --- Install / upgrade ---
echo ">>> Installing/upgrading release '${RELEASE}'..."
helm "${HELM_ARGS[@]}"

echo ""
echo "=== Installed successfully ==="
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE}"

# --- Wait for Gateway to be fully ready and print dashboard URL ---
echo ""
echo ">>> Waiting for Gateway to become ready..."
DASHBOARD_URL=""
MAX_ATTEMPTS=30
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
  URL=$(kubectl -n "${NAMESPACE}" exec "${RELEASE}-gateway-0" -c gateway -- \
    node dist/index.js dashboard --no-open 2>/dev/null | grep "Dashboard URL:" || true)
  if [[ -n "${URL}" ]]; then
    DASHBOARD_URL="${URL#*Dashboard URL: }"
    break
  fi
  if [[ "${i}" -eq "${MAX_ATTEMPTS}" ]]; then
    echo "WARNING: Could not retrieve dashboard URL after ${MAX_ATTEMPTS} attempts."
    echo "The Gateway may still be starting. Try manually:"
    echo "  kubectl -n ${NAMESPACE} exec ${RELEASE}-gateway-0 -c gateway -- node dist/index.js dashboard --no-open"
    break
  fi
  sleep 2
done

# --- Port-forward for local access ---
LOCAL_PORT="${LOCAL_PORT:-18789}"

echo ""
echo ">>> Starting port-forward (localhost:${LOCAL_PORT} -> ${RELEASE}-gateway:18789)..."
kubectl port-forward -n "${NAMESPACE}" "svc/${RELEASE}-gateway" "${LOCAL_PORT}:18789" &
PF_PID=$!

# Give port-forward a moment to bind
sleep 2
if kill -0 "${PF_PID}" 2>/dev/null; then
  echo "Port-forward running (PID ${PF_PID}). Stop with: kill ${PF_PID}"
else
  echo "WARNING: Port-forward failed to start. Run manually:"
  echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-gateway ${LOCAL_PORT}:18789"
fi

if [[ -n "${DASHBOARD_URL}" ]]; then
  # Rewrite the dashboard URL to use localhost
  LOCAL_URL=$(echo "${DASHBOARD_URL}" | sed "s|http://[^/]*|http://localhost:${LOCAL_PORT}|")
  echo ""
  echo "Open in your browser: ${LOCAL_URL}"
fi
