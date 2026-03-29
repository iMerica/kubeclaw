#!/usr/bin/env bash
#
# Installs (or upgrades) the kubeclaw Helm chart from OCI.
# Just run: ./scripts/install.sh
#
# All variables have defaults below — edit them in-place for your environment.
# Any variable can also be overridden via environment:
#   NAMESPACE=prod ./scripts/install.sh
#
set -euo pipefail

# Disown background jobs on exit so the port-forward survives and the shell
# does not report a non-zero exit from a killed background process.
cleanup() { jobs -p | xargs -r disown 2>/dev/null; }
trap cleanup EXIT

# --- Configuration (edit these or override via environment) -----------------
RELEASE="${RELEASE:-kubeclaw}"
NAMESPACE="${NAMESPACE:-kubeclaw}"

# Chart source: installers pull the latest chart by default.
CHART_REF="${CHART_REF:-oci://ghcr.io/imerica/kubeclaw}"

# Gateway auth token (secret.data.OPENCLAW_GATEWAY_TOKEN)
OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"

# LiteLLM proxy master key — must start with "sk-" (required when litellm is enabled)
LITELLM_MASTERKEY="${LITELLM_MASTERKEY:-sk-changeme}"

# Tailscale auth key — required when tailscale.ssh.enabled=true (the default).
# Accepts either TS_AUTHKEY or TAILSCALE_AUTH_KEY from the environment.
TS_AUTHKEY="${TS_AUTHKEY:-${TAILSCALE_AUTH_KEY:-}}"

# Provider API keys — passed to both the Gateway and LiteLLM proxy
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Optional GitHub token for gh CLI + GitHub skill auth in-pod
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"


# Optional: path to a custom values file layered on top of chart defaults
VALUES_FILE="${VALUES_FILE:-}"
# ----------------------------------------------------------------------------

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
  upgrade --install "${RELEASE}" "${CHART_REF}"
  --namespace "${NAMESPACE}"
  --set "secret.create=true"
  --set "secret.data.OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
  --set "litellm.masterkey=${LITELLM_MASTERKEY}"
  --set "secret.data.OPENAI_API_KEY=${OPENAI_API_KEY}"
  --set "tailscale.ssh.authKey=${TS_AUTHKEY}"
  --wait
  --timeout 5m
)

if [[ -n "${GITHUB_TOKEN}" ]]; then
  HELM_ARGS+=(--set "github.auth.token=${GITHUB_TOKEN}")
fi

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
echo "Chart:     ${CHART_REF}"
echo "Tailscale: ${TS_AUTHKEY:0:12}***"
if [[ -n "${GITHUB_TOKEN}" ]]; then
  echo "GitHub:    ${GITHUB_TOKEN:0:12}***"
else
  echo "GitHub:    not configured (optional)"
fi
echo ""

# For local chart directories, ensure dependencies are present.
if [[ "${CHART_REF}" != oci://* ]] && [[ -d "${CHART_REF}" ]] && [[ -f "${CHART_REF}/Chart.yaml" ]]; then
  echo ">>> Resolving local chart dependencies..."
  helm dependency update "${CHART_REF}" --skip-refresh 2>/dev/null || helm dependency build "${CHART_REF}"
fi

# --- Install / upgrade ---
echo ">>> Installing/upgrading release '${RELEASE}'..."
helm "${HELM_ARGS[@]}"

echo ""
echo "=== Installed successfully ==="
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE}"

# --- Wait for Gateway to be fully ready ---
echo ""
echo ">>> Waiting for Gateway to become ready..."
MAX_ATTEMPTS=30
GATEWAY_READY=false
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
  if kubectl -n "${NAMESPACE}" exec "${RELEASE}-gateway-0" -c gateway -- \
    node dist/index.js dashboard --no-open &>/dev/null; then
    GATEWAY_READY=true
    break
  fi
  if [[ "${i}" -eq "${MAX_ATTEMPTS}" ]]; then
    echo "WARNING: Gateway not ready after ${MAX_ATTEMPTS} attempts. It may still be starting."
    break
  fi
  sleep 2
done
if [[ "${GATEWAY_READY}" == true ]]; then
  echo "Gateway is ready."
fi

# --- Wait for K8s Gateway API to become PROGRAMMED ---
GW_NAME="${RELEASE}-gateway-api"
echo ""
echo ">>> Waiting for K8s Gateway API to become programmed..."
GW_PROGRAMMED=false
for i in $(seq 1 30); do
  PROGRAMMED=$(kubectl get gateway "${GW_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "")
  if [[ "${PROGRAMMED}" == "True" ]]; then
    GW_PROGRAMMED=true
    break
  fi
  sleep 2
done

if [[ "${GW_PROGRAMMED}" == true ]]; then
  echo "Gateway '${GW_NAME}' is programmed."
else
  echo "WARNING: Gateway '${GW_NAME}' is not yet programmed."
  echo "  Check status: kubectl describe gateway ${GW_NAME} -n ${NAMESPACE}"
fi

# --- Discover Envoy proxy service for port-forwarding ---
GW_PORT=$(kubectl get svc -n "${NAMESPACE}" \
  -l "gateway.envoyproxy.io/owning-gateway-name=${GW_NAME}" \
  -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null || echo "80")
ENVOY_SVC=$(kubectl get svc -n "${NAMESPACE}" \
  -l "gateway.envoyproxy.io/owning-gateway-name=${GW_NAME}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

LOCAL_PORT="${LOCAL_PORT:-8080}"

echo ""
echo "=== Routes ==="
BASE_URL="http://localhost:${LOCAL_PORT}"
TOKEN_QS="?token=${OPENCLAW_GATEWAY_TOKEN}"

echo ""
echo "  OpenClaw Gateway (primary):"
echo "    ${BASE_URL}/${TOKEN_QS}"
echo ""
echo "  Ancillary services:"
ROUTES=$(kubectl get httproute -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE}" \
  -o jsonpath='{range .items[*]}{.spec.rules[0].matches[0].path.value}{"\n"}{end}' 2>/dev/null || true)

if [[ -n "${ROUTES}" ]]; then
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    # Skip the root route (already shown above) and headless API-only services
    [[ "${path}" == "/" || "${path}" == "/filtering" ]] && continue
    echo "    ${BASE_URL}${path}"
  done <<< "${ROUTES}"
fi

# --- Port-forward for local access ---
echo ""
if [[ -n "${ENVOY_SVC}" ]]; then
  echo ">>> Starting port-forward (localhost:${LOCAL_PORT} -> ${ENVOY_SVC}:${GW_PORT})..."
  kubectl port-forward -n "${NAMESPACE}" "svc/${ENVOY_SVC}" "${LOCAL_PORT}:${GW_PORT}" &
else
  echo ">>> Gateway API proxy not found, falling back to direct gateway service..."
  echo ">>> Starting port-forward (localhost:${LOCAL_PORT} -> ${RELEASE}-gateway:18789)..."
  kubectl port-forward -n "${NAMESPACE}" "svc/${RELEASE}-gateway" "${LOCAL_PORT}:18789" &
fi
PF_PID=$!
disown "${PF_PID}" 2>/dev/null || true

# Give port-forward a moment to bind
sleep 2
if kill -0 "${PF_PID}" 2>/dev/null; then
  echo "Port-forward running (PID ${PF_PID}). Stop with: kill ${PF_PID}"
else
  echo "WARNING: Port-forward failed to start. Run manually:"
  if [[ -n "${ENVOY_SVC}" ]]; then
    echo "  kubectl port-forward -n ${NAMESPACE} svc/${ENVOY_SVC} ${LOCAL_PORT}:${GW_PORT}"
  else
    echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-gateway ${LOCAL_PORT}:18789"
  fi
fi

echo ""
echo "=== Ready ==="
echo "Open in your browser: ${BASE_URL}/${TOKEN_QS}"
