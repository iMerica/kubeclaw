#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.json}"
OUT_QMD_DIR="${OUT_QMD_DIR:-/out/opt/kubeclaw/qmd-bin}"
OUT_QMD_PREFIX="${OUT_QMD_PREFIX:-/out/opt/kubeclaw/qmd}"

enabled="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String(Boolean(p.qmd && p.qmd.enabled)));' "$PACKAGES_FILE")"
if [ "$enabled" != "true" ]; then
  exit 0
fi

package_url="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String((p.qmd && p.qmd.packageUrl) || ""));' "$PACKAGES_FILE")"
expected_integrity="$(node -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String((p.qmd && p.qmd.integrity) || ""));' "$PACKAGES_FILE")"
if [ -z "$package_url" ]; then
  echo "qmd.packageUrl must be set when qmd.enabled=true" >&2
  exit 1
fi
if [ -z "$expected_integrity" ]; then
  echo "qmd.integrity must be set when qmd.enabled=true" >&2
  exit 1
fi

metadata="$(EXPECTED_INTEGRITY="$expected_integrity" node -e '
  const https = require("https");
  const spec = process.argv[1];

  const lastAt = spec.lastIndexOf("@");
  if (lastAt <= 0) {
    process.stderr.write("qmd.packageUrl must include an explicit version\n");
    process.exit(1);
  }

  const pkg = spec.slice(0, lastAt);
  const version = spec.slice(lastAt + 1);
  if (!pkg || !version) {
    process.stderr.write("invalid qmd.packageUrl\n");
    process.exit(1);
  }

  const encoded = pkg.replace("/", "%2f");
  const url = `https://registry.npmjs.org/${encoded}/${version}`;
  https.get(url, { headers: { "User-Agent": "kubeclaw-image-build" } }, (res) => {
    const chunks = [];
    res.on("data", (c) => chunks.push(c));
    res.on("end", () => {
      if (res.statusCode !== 200) {
        process.stderr.write(`failed to fetch ${url}: status ${res.statusCode}\n`);
        process.exit(1);
      }

      const data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      if (!data.dist || !data.dist.tarball || !data.dist.integrity) {
        process.stderr.write("npm metadata missing dist.tarball or dist.integrity\n");
        process.exit(1);
      }
      if (process.env.EXPECTED_INTEGRITY && process.env.EXPECTED_INTEGRITY !== data.dist.integrity) {
        process.stderr.write("qmd integrity mismatch against packages.json\n");
        process.exit(1);
      }

      process.stdout.write(String(data.dist.tarball) + "|" + String(data.dist.integrity));
    });
  }).on("error", (err) => {
    process.stderr.write(String(err.message) + "\n");
    process.exit(1);
  });
' "$package_url")"

tarball_url="${metadata%%|*}"
resolved_integrity="${metadata#*|}"

if [ -z "$tarball_url" ] || [ -z "$resolved_integrity" ]; then
  echo "failed to resolve qmd tarball metadata" >&2
  exit 1
fi

archive="/tmp/qmd.tgz"
curl -fsSL "$tarball_url" -o "$archive"

case "$resolved_integrity" in
  sha512-*)
    actual_sha="$(openssl dgst -sha512 -binary "$archive" | openssl base64 -A)"
    expected_sha="${resolved_integrity#sha512-}"
    if [ "$actual_sha" != "$expected_sha" ]; then
      echo "qmd tarball sha512 verification failed" >&2
      exit 1
    fi
    ;;
  *)
    echo "unsupported qmd integrity format: $resolved_integrity" >&2
    exit 1
    ;;
esac

mkdir -p "$OUT_QMD_PREFIX" "$OUT_QMD_DIR"
npm install --prefix "$OUT_QMD_PREFIX" --cache /tmp/.npm --no-save --no-audit --no-fund "$archive" >/dev/null

qmd_bin="$OUT_QMD_PREFIX/node_modules/.bin/qmd"
if [ ! -x "$qmd_bin" ]; then
  echo "qmd binary not found after install" >&2
  exit 1
fi

cat > "$OUT_QMD_DIR/qmd" <<'EOF'
#!/bin/sh
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../qmd/node_modules/.bin/qmd" "$@"
EOF

cat > "$OUT_QMD_DIR/qmd.js" <<'EOF'
#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const qmdCli = resolve(scriptDir, "../qmd/node_modules/.bin/qmd");
const result = spawnSync(qmdCli, process.argv.slice(2), { stdio: "inherit" });

if (result.error) {
  process.stderr.write(`${result.error.message}\n`);
  process.exit(1);
}

if (typeof result.status === "number") {
  process.exit(result.status);
}

process.exit(1);
EOF

node -e '
  const pkgRoot = process.argv[1];
  const required = ["fast-glob", "better-sqlite3", "node-llama-cpp", "sqlite-vec", "yaml", "zod"];
  for (const name of required) {
    require.resolve(name, { paths: [pkgRoot] });
  }
' "$OUT_QMD_PREFIX/node_modules/@tobilu/qmd"

"$qmd_bin" --help >/dev/null
chmod 0555 "$OUT_QMD_DIR/qmd" "$OUT_QMD_DIR/qmd.js" 2>/dev/null || true
"$OUT_QMD_DIR/qmd" --help >/dev/null
node "$OUT_QMD_DIR/qmd.js" --help >/dev/null
