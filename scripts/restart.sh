#!/usr/bin/env bash
#
# Destroys and reinstalls the kubeclaw Helm chart.
# Just run: ./scripts/restart.sh
#
# Inherits all configuration from destroy.sh and install.sh.
# Override any variable via environment:
#   NAMESPACE=prod ./scripts/restart.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"${SCRIPT_DIR}/destroy.sh"
echo ""
"${SCRIPT_DIR}/install.sh"
