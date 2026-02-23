#!/usr/bin/env bash
#
# Destroys and reinstalls the kubeclaw Helm chart.
# WARNING: This deletes all PVCs and state. Data will be lost.
# Just run: ./scripts/reinstall.sh
#
# Inherits all configuration from destroy.sh and install.sh.
# Override any variable via environment:
#   NAMESPACE=prod ./scripts/reinstall.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/destroy.sh"
echo ""
"${SCRIPT_DIR}/install.sh"
