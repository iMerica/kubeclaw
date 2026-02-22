#!/usr/bin/env bash
# scan-local.sh — Run all four security/best-practices scanners locally.
# Usage: ./scripts/scan-local.sh
set -euo pipefail

CHART_DIR="charts/openclaw"
RENDERED="/tmp/openclaw-scan-rendered.yaml"
PASS=0
FAIL=0
SKIP=0

# Resolve chart dir relative to repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_PATH="$REPO_ROOT/$CHART_DIR"

check_tool() {
  if command -v "$1" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

print_install_hint() {
  local tool="$1"
  case "$tool" in
    kubeconform)
      echo "  brew install kubeconform        # macOS"
      echo "  go install github.com/yannh/kubeconform/cmd/kubeconform@latest  # Go"
      ;;
    kube-linter)
      echo "  brew install kube-linter        # macOS"
      echo "  go install golang.stackrox.io/kube-linter/cmd/kube-linter@latest  # Go"
      ;;
    trivy)
      echo "  brew install trivy              # macOS"
      echo "  See https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
      ;;
    checkov)
      echo "  brew install checkov            # macOS"
      echo "  pip install checkov             # pip"
      ;;
  esac
}

separator() {
  echo ""
  echo "================================================================"
  echo "$1"
  echo "================================================================"
}

# --- Render chart -----------------------------------------------------------
separator "Rendering Helm chart"
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm is not installed. Install it first."
  exit 1
fi

helm template openclaw "$CHART_PATH" \
  --set secret.create=true \
  --set secret.data.OPENCLAW_GATEWAY_TOKEN=local-scan-token \
  > "$RENDERED"
echo "Rendered to $RENDERED"

# --- Kubeconform ------------------------------------------------------------
separator "Kubeconform (manifest validation)"
if check_tool kubeconform; then
  if kubeconform -summary -strict -kubernetes-version 1.25.0 -output text "$RENDERED"; then
    echo "RESULT: PASS"
    PASS=$((PASS + 1))
  else
    echo "RESULT: FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIPPED: kubeconform not installed."
  print_install_hint kubeconform
  SKIP=$((SKIP + 1))
fi

# --- Kube-linter ------------------------------------------------------------
separator "Kube-linter (best practices)"
if check_tool kube-linter; then
  if kube-linter lint "$RENDERED"; then
    echo "RESULT: PASS"
    PASS=$((PASS + 1))
  else
    echo "RESULT: FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIPPED: kube-linter not installed."
  print_install_hint kube-linter
  SKIP=$((SKIP + 1))
fi

# --- Trivy ------------------------------------------------------------------
separator "Trivy (misconfiguration scan)"
if check_tool trivy; then
  if trivy config --severity HIGH,CRITICAL --exit-code 1 "$CHART_PATH"; then
    echo "RESULT: PASS"
    PASS=$((PASS + 1))
  else
    echo "RESULT: FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIPPED: trivy not installed."
  print_install_hint trivy
  SKIP=$((SKIP + 1))
fi

# --- Checkov ----------------------------------------------------------------
separator "Checkov (policy-as-code)"
if check_tool checkov; then
  if checkov --directory "$CHART_PATH" --framework helm --quiet --compact --soft-fail; then
    echo "RESULT: PASS"
    PASS=$((PASS + 1))
  else
    echo "RESULT: FAIL"
    FAIL=$((FAIL + 1))
  fi
else
  echo "SKIPPED: checkov not installed."
  print_install_hint checkov
  SKIP=$((SKIP + 1))
fi

# --- Summary ----------------------------------------------------------------
separator "Summary"
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
echo "  Skipped: $SKIP"

if [[ "$SKIP" -gt 0 ]]; then
  echo ""
  echo "Install missing tools:"
  echo "  brew install kubeconform kube-linter trivy checkov"
fi

rm -f "$RENDERED"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
