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

# Return all GatewayClass names managed by the Envoy Gateway controller.
get_envoy_gatewayclasses() {
  kubectl get gatewayclass -o jsonpath="{range .items[?(@.spec.controllerName==\"${ENVOY_GATEWAY_CONTROLLER_NAME}\")]}{.metadata.name}{' '}{end}" 2>/dev/null || true
}

# Strip finalizers from all resources of a given kind so they don't block deletion.
# Usage: strip_finalizers <kind> [--namespace <ns>] [-l <selector>] [--field-selector ...]
strip_finalizers() {
  local kind="$1"; shift
  local names
  names=$(kubectl get "${kind}" "$@" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null) || return 0
  for name in ${names}; do
    kubectl patch "${kind}" "${name}" "$@" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
  done
}

echo "=== KubeClaw Destroy ==="
echo "Release:   ${RELEASE}"
echo "Namespace: ${NAMESPACE}"
echo "Selector:  ${LABEL_SELECTOR}"
echo ""

# --- 1. Strip finalizers from Gateway API resources before anything else ---
echo ">>> Stripping finalizers from Gateway API resources..."
for kind in gateway httproute; do
  strip_finalizers "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" 2>/dev/null || true
done
# GatewayClass is cluster-scoped; strip finalizers from all Envoy-managed classes.
for gatewayclass in $(get_envoy_gatewayclasses); do
  kubectl patch gatewayclass "${gatewayclass}" --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
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

# --- 4. Delete Gateway API resources ---
echo ">>> Deleting Gateway API resources..."
for kind in gateway httproute; do
  kubectl delete "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done
for gatewayclass in $(get_envoy_gatewayclasses); do
  kubectl delete gatewayclass "${gatewayclass}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 5. Delete cluster-scoped resources by label ---
echo ">>> Cleaning up cluster-scoped resources..."
for kind in clusterrole clusterrolebinding; do
  kubectl delete "${kind}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 6. Delete Envoy Gateway system namespace ---
if kubectl get namespace "${ENVOY_GATEWAY_NAMESPACE}" &>/dev/null; then
  echo ">>> Deleting ${ENVOY_GATEWAY_NAMESPACE} namespace..."
  kubectl delete namespace "${ENVOY_GATEWAY_NAMESPACE}" --wait=false 2>/dev/null || true
fi

# --- 7. Delete all namespaced resources by instance label ---
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

# --- 8. Delete PVCs by StatefulSet naming convention (in case labels were stripped) ---
# Patterns cover: primary state, split workspace, Obsidian vault, and Tailscale state (persistState=true)
for pattern in "${RELEASE}-kubeclaw-state" "${RELEASE}-kubeclaw-workspace" "${RELEASE}-kubeclaw-obsidian" "ts-state-${RELEASE}-kubeclaw"; do
  pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o name 2>/dev/null | grep "${pattern}" || true)
  if [[ -n "${pvcs}" ]]; then
    echo ">>> Deleting PVCs matching '${pattern}'..."
    echo "${pvcs}" | xargs kubectl delete -n "${NAMESPACE}" --ignore-not-found --wait=false
  fi
done

# --- 9. Wait for pods to terminate ---
echo ">>> Waiting for pods to terminate..."
kubectl wait pod -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=60s 2>/dev/null || true

# --- 10. Verify nothing remains ---
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
