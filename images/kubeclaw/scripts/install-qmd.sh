#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.json}"
OUT_QMD_DIR="${OUT_QMD_DIR:-/out/opt/kubeclaw/qmd-bin}"

enabled="$(bun -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String(Boolean(p.qmd && p.qmd.enabled)));' "$PACKAGES_FILE")"
if [ "$enabled" != "true" ]; then
  exit 0
fi

package_url="$(bun -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String(p.qmd.packageUrl));' "$PACKAGES_FILE")"
expected_integrity="$(bun -e 'const fs=require("fs"); const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(String((p.qmd && p.qmd.integrity) || ""));' "$PACKAGES_FILE")"
if [ -z "$expected_integrity" ]; then
  echo "qmd.integrity must be set when qmd.enabled=true" >&2
  exit 1
fi

# shellcheck disable=SC2016
tarball_url="$(EXPECTED_INTEGRITY="$expected_integrity" bun -e '
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
      process.stdout.write(String(data.dist.tarball));
    });
  }).on("error", (err) => {
    process.stderr.write(String(err.message) + "\n");
    process.exit(1);
  });
' "$package_url")"

# shellcheck disable=SC2016
resolved_integrity="$(bun -e '
  const https = require("https");
  const spec = process.argv[1];
  const lastAt = spec.lastIndexOf("@");
  const pkg = spec.slice(0, lastAt);
  const version = spec.slice(lastAt + 1);
  const encoded = pkg.replace("/", "%2f");
  const url = `https://registry.npmjs.org/${encoded}/${version}`;
  https.get(url, { headers: { "User-Agent": "kubeclaw-image-build" } }, (res) => {
    const chunks = [];
    res.on("data", (c) => chunks.push(c));
    res.on("end", () => {
      if (res.statusCode !== 200) process.exit(1);
      const data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      process.stdout.write(String(data.dist.integrity));
    });
  }).on("error", () => process.exit(1));
' "$package_url")"

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

mkdir -p "$OUT_QMD_DIR"
bun install -g --ignore-scripts "$archive"

bun_bin="$(which bun)"
qmd_bin="$(which qmd || true)"

if [ -z "$qmd_bin" ]; then
  for p in "$HOME/.bun/bin/qmd" "/root/.bun/bin/qmd"; do
    if [ -x "$p" ]; then
      qmd_bin="$p"
      break
    fi
  done
fi

if [ -z "$qmd_bin" ]; then
  echo "qmd binary not found after install" >&2
  exit 1
fi

cp "$bun_bin" "$OUT_QMD_DIR/bun"
cp "$qmd_bin" "$OUT_QMD_DIR/qmd"
chmod 0555 "$OUT_QMD_DIR/bun" "$OUT_QMD_DIR/qmd"

bun_global_dir="$(dirname "$(dirname "$qmd_bin")")"
if [ -d "$bun_global_dir/node_modules" ]; then
  cp -r "$bun_global_dir/node_modules" "$OUT_QMD_DIR/node_modules"
fi
