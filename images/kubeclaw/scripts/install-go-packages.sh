#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.json}"
OUT_BIN_DIR="${OUT_BIN_DIR:-/out/opt/kubeclaw/bin}"

count="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String((p.goPackages||[]).length));' "$PACKAGES_FILE")"
if [ "$count" = "0" ]; then
  exit 0
fi

mkdir -p "$OUT_BIN_DIR"

node -e '
  const fs = require("fs");
  const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const item of (p.goPackages || [])) {
    process.stdout.write(item + "\n");
  }
' "$PACKAGES_FILE" | while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  GOBIN="$OUT_BIN_DIR" go install "$pkg"
done
