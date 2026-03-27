#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/opt/kubeclaw/packages.json}"

linux_packages="$(node -e '
  const fs = require("fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  process.stdout.write((p.linuxPackages || []).join("\n"));
' "$PACKAGES_FILE")"

[ -n "$linux_packages" ] || exit 0

set --
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  set -- "$@" "$pkg"
done <<EOF
$linux_packages
EOF

[ "$#" -gt 0 ] || exit 0

if [ -f /etc/alpine-release ]; then
  apk add --no-cache "$@"
elif [ -f /etc/debian_version ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "$@"
  rm -rf /var/lib/apt/lists/*
else
  echo "Unsupported base image for linuxPackages install" >&2
  exit 1
fi
