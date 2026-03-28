#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/opt/kubeclaw/packages.json}"

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

node -e '
  const fs = require("fs");
  const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const item of (pkg.skillsSh || [])) {
    if (!item || typeof item !== "object") continue;
    const url = typeof item.url === "string" ? item.url.trim() : "";
    const sha256 = typeof item.sha256 === "string" ? item.sha256.trim() : "";
    if (!url || !sha256) continue;
    process.stdout.write(JSON.stringify({ url, sha256 }) + "\n");
  }
 ' "$PACKAGES_FILE" | while IFS= read -r line; do
  [ -n "$line" ] || continue
  url="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.url);' "$line")"
  expected_sha="$(node -e 'const x=JSON.parse(process.argv[1]); process.stdout.write(x.sha256);' "$line")"

  case "$url" in
    https://*) ;;
    *)
      echo "skillsSh.url must use https: $url" >&2
      exit 1
      ;;
  esac

  tmp_script="$(mktemp /tmp/skills-sh.XXXXXX.sh)"
  curl -fsSL "$url" -o "$tmp_script"
  actual_sha="$(sha256_file "$tmp_script")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "skillsSh checksum mismatch for $url" >&2
    echo "expected: $expected_sha" >&2
    echo "actual:   $actual_sha" >&2
    rm -f "$tmp_script"
    exit 1
  fi

  chmod 0555 "$tmp_script"
  sh "$tmp_script"
  rm -f "$tmp_script"
done
