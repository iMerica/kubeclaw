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
  helm uninstall "${RELEASE}" -n "${NAMESPACE}" --wait
else
  echo ">>> Helm release '${RELEASE}' not found, skipping uninstall."
fi

# --- 2. Delete all resources by instance label (catches subchart resources too) ---
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

# --- 3. Delete PVCs by StatefulSet naming convention (in case labels were stripped) ---
for pattern in "${RELEASE}-kubeclaw-state" "${RELEASE}-kubeclaw-workspace"; do
  pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o name 2>/dev/null | grep "${pattern}" || true)
  if [[ -n "${pvcs}" ]]; then
    echo ">>> Deleting PVCs matching '${pattern}'..."
    echo "${pvcs}" | xargs kubectl delete -n "${NAMESPACE}" --ignore-not-found --wait=false
  fi
done

# --- 4. Wait for all pods to terminate ---
echo ">>> Waiting for pods to terminate..."
kubectl wait pod -n "${NAMESPACE}" -l "${LABEL_SELECTOR}" --for=delete --timeout=120s 2>/dev/null || true

# --- 5. Verify nothing remains ---
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
