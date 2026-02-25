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

LABEL_SELECTOR="app.kubernetes.io/instance=${RELEASE}"

echo "=== KubeClaw Destroy ==="
echo "Release:   ${RELEASE}"
echo "Namespace: ${NAMESPACE}"
echo "Selector:  ${LABEL_SELECTOR}"
echo ""

# --- 1. Uninstall the Helm release (removes all managed resources) ---
if helm status "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
  echo ">>> Uninstalling Helm release '${RELEASE}'..."
  # Use a timeout to avoid hanging on stuck finalizers (e.g. Envoy Gateway).
  helm uninstall "${RELEASE}" -n "${NAMESPACE}" --wait --timeout 60s || {
    echo ">>> helm uninstall timed out or failed; forcing without --wait..."
    helm uninstall "${RELEASE}" -n "${NAMESPACE}" --no-hooks 2>/dev/null || true
  }
else
  echo ">>> Helm release '${RELEASE}' not found, skipping uninstall."
fi

# --- 2. Remove Gateway API resources (these can have finalizers that block deletion) ---
echo ">>> Cleaning up Gateway API resources..."
for kind in gateway httproute; do
  kubectl delete "${kind}" -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --ignore-not-found --timeout=30s 2>/dev/null || true
done
# GatewayClass is cluster-scoped; delete by name if it was created by the controller subchart.
kubectl delete gatewayclass envoy --ignore-not-found --timeout=30s 2>/dev/null || true

# --- 3. Clean up cluster-scoped resources by label ---
echo ">>> Cleaning up cluster-scoped resources..."
for kind in clusterrole clusterrolebinding; do
  kubectl delete "${kind}" -l "${LABEL_SELECTOR}" --ignore-not-found --wait=false 2>/dev/null || true
done

# --- 4. Delete Envoy Gateway system namespace if it exists ---
# The Envoy Gateway subchart creates an envoy-gateway-system namespace with a
# running controller. This must be removed or the controller pod lingers.
if kubectl get namespace envoy-gateway-system &>/dev/null; then
  echo ">>> Deleting envoy-gateway-system namespace..."
  kubectl delete namespace envoy-gateway-system --timeout=60s 2>/dev/null || true
fi

# --- 6. Delete all namespaced resources by instance label (catches subchart resources too) ---
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

# --- 7. Delete PVCs by StatefulSet naming convention (in case labels were stripped) ---
# Patterns cover: primary state, split workspace, and Tailscale state (persistState=true)
for pattern in "${RELEASE}-kubeclaw-state" "${RELEASE}-kubeclaw-workspace" "ts-state-${RELEASE}-kubeclaw"; do
  pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o name 2>/dev/null | grep "${pattern}" || true)
  if [[ -n "${pvcs}" ]]; then
    echo ">>> Deleting PVCs matching '${pattern}'..."
    echo "${pvcs}" | xargs kubectl delete -n "${NAMESPACE}" --ignore-not-found --wait=false
  fi
done

# --- 8. Wait for all pods to terminate ---
echo ">>> Waiting for pods to terminate..."
kubectl wait pod -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=120s 2>/dev/null || true

# --- 9. Verify nothing remains ---
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
