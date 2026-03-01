#!/usr/bin/env bash
#
# Completely destroys all resources created by the kubeclaw Helm chart.
# Just run: ./scripts/destroy.sh
#
# All variables have defaults below. Override any of them via environment:
#   RELEASE=myrelease NAMESPACE=prod ./scripts/destroy.sh
#
set -euo pipefail

# --- Configuration (edit these or override via environment) ---
RELEASE="${RELEASE:-kubeclaw}"
NAMESPACE="${NAMESPACE:-kubeclaw}"
ENVOY_GATEWAY_NAMESPACE="${ENVOY_GATEWAY_NAMESPACE:-envoy-gateway-system}"
ENVOY_GATEWAY_CONTROLLER_NAME="${ENVOY_GATEWAY_CONTROLLER_NAME:-gateway.envoyproxy.io/gatewayclass-controller}"

LABEL_SELECTOR="app.kubernetes.io/instance=${RELEASE}"

# Return GatewayClass names managed by this Helm release and Envoy controller.
get_envoy_gatewayclasses() {
  local names
  names=$(kubectl get gatewayclass -l "${LABEL_SELECTOR}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || return 0
  for name in ${names}; do
    controller=$(kubectl get gatewayclass "${name}" -o jsonpath='{.spec.controllerName}' 2>/dev/null || true)
    if [[ "${controller}" == "${ENVOY_GATEWAY_CONTROLLER_NAME}" ]]; then
      printf "%s " "${name}"
    fi
  done
}

# Strip finalizers from all resources of a given kind so they don't block deletion.
# Usage: strip_finalizers <kind> [--namespace <ns>] [-l <selector>] [--field-selector ...]
strip_finalizers() {
  local kind="$1"; shift
  local names
  local namespace_args=()
  local args=("$@")
  local i

  names=$(kubectl get "${kind}" "$@" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || return 0

  # Keep only namespace flags for per-object patch calls; selectors are invalid with a named patch.
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "-n" || "${args[$i]}" == "--namespace" ]]; then
      if (( i + 1 < ${#args[@]} )); then
        namespace_args=("${args[$i]}" "${args[$((i + 1))]}")
      fi
      break
    fi
  done

  for name in ${names}; do
    kubectl patch "${kind}" "${name}" "${namespace_args[@]}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
}

echo "=== KubeClaw Destroy ==="
echo "Release:   ${RELEASE}"
echo "Namespace: ${NAMESPACE}"
echo "Selector:  ${LABEL_SELECTOR}"
echo ""

# --- 1. Strip finalizers from namespaced Gateway API resources before uninstall ---
echo ">>> Stripping finalizers from namespaced Gateway API resources..."
for kind in gateway httproute; do
  strip_finalizers "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" 2>/dev/null || true
done

# --- 2. Strip finalizers from Envoy Gateway system resources ---
if kubectl get namespace "${ENVOY_GATEWAY_NAMESPACE}" &>/dev/null; then
  echo ">>> Stripping finalizers from ${ENVOY_GATEWAY_NAMESPACE} resources..."
  for kind in deployment service configmap secret serviceaccount; do
    strip_finalizers "${kind}" -n "${ENVOY_GATEWAY_NAMESPACE}"
  done
fi

# --- 3. Uninstall the Helm release ---
if helm status "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
  echo ">>> Uninstalling Helm release '${RELEASE}'..."
  helm uninstall "${RELEASE}" -n "${NAMESPACE}" --wait --timeout 60s || {
    echo ">>> helm uninstall timed out; retrying without hooks..."
    helm uninstall "${RELEASE}" -n "${NAMESPACE}" --no-hooks 2>/dev/null || true
  }
else
  echo ">>> Helm release '${RELEASE}' not found, skipping uninstall."
fi

# --- 4. Delete Envoy Gateway managed resources (proxy Deployments, Services, etc.) ---
# The Envoy Gateway controller creates its own resources (proxy Deployment,
# Service, ConfigMap) that are NOT managed by Helm. If these linger across
# reinstalls the proxy can start in DRAINING state and never become ready.
ENVOY_MANAGED_LABEL="app.kubernetes.io/managed-by=envoy-gateway"
echo ">>> Deleting Envoy Gateway managed resources..."
for kind in deployment service configmap secret; do
  kubectl delete "${kind}" -n "${NAMESPACE}" -l "${ENVOY_MANAGED_LABEL}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 5. Delete Gateway API resources ---
echo ">>> Deleting Gateway API resources..."
for kind in gateway httproute; do
  kubectl delete "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done
# Give namespaced Gateway API resources a chance to disappear so GatewayClass finalizer can clear naturally.
kubectl wait gateway -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=60s 2>/dev/null || true
kubectl wait httproute -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=60s 2>/dev/null || true

for gatewayclass in $(get_envoy_gatewayclasses); do
  kubectl delete gatewayclass "${gatewayclass}" --ignore-not-found --wait=false 2>/dev/null || true
  # If finalizer is still present after Gateway deletion, clear it as a fallback.
  kubectl patch gatewayclass "${gatewayclass}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  kubectl delete gatewayclass "${gatewayclass}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 6. Delete cluster-scoped resources by label ---
echo ">>> Cleaning up cluster-scoped resources..."
for kind in clusterrole clusterrolebinding; do
  kubectl delete "${kind}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 7. Delete Envoy Gateway system namespace ---
if kubectl get namespace "${ENVOY_GATEWAY_NAMESPACE}" &>/dev/null; then
  echo ">>> Deleting ${ENVOY_GATEWAY_NAMESPACE} namespace..."
  kubectl delete namespace "${ENVOY_GATEWAY_NAMESPACE}" --wait=false 2>/dev/null || true
fi

# --- 8. Delete all namespaced resources by instance label ---
RESOURCE_TYPES=(
  statefulset
  deployment
  replicaset
  cronjob
  job
  pod
  service
  secret
  configmap
  serviceaccount
  ingress
  networkpolicy
  pvc
)

echo ">>> Deleting all labeled resources..."
for kind in "${RESOURCE_TYPES[@]}"; do
  kubectl delete "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 9. Delete PVCs by StatefulSet naming convention (in case labels were stripped) ---
# Patterns cover: primary state, split workspace, Obsidian vault, and Tailscale state (persistState=true)
for pattern in "${RELEASE}-kubeclaw-state" "${RELEASE}-kubeclaw-workspace" "${RELEASE}-kubeclaw-obsidian" "ts-state-${RELEASE}-kubeclaw"; do
  pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o name 2>/dev/null | grep "${pattern}" || true)
  if [[ -n "${pvcs}" ]]; then
    echo ">>> Deleting PVCs matching '${pattern}'..."
    echo "${pvcs}" | xargs kubectl delete -n "${NAMESPACE}" --ignore-not-found --wait=false
  fi
done

# --- 10. Wait for pods to terminate ---
echo ">>> Waiting for pods to terminate..."
kubectl wait pod -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=60s 2>/dev/null || true

# --- 11. Verify nothing remains ---
echo ""
echo "=== Verification ==="
remaining=$(kubectl get all,secret,configmap,pvc,ingress,networkpolicy,serviceaccount \
  -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --no-headers 2>/dev/null | grep -v "^$" || true)

if [[ -n "${remaining}" ]]; then
  echo "WARNING: The following resources still exist:"
  echo "${remaining}"
  exit 1
else
  echo "All resources for release '${RELEASE}' in namespace '${NAMESPACE}' have been removed."
fi
