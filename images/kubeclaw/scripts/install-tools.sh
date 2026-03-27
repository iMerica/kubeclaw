#!/bin/sh
set -eu

PACKAGES_FILE="${PACKAGES_FILE:-/workspace/packages.json}"
OUT_BIN_DIR="${OUT_BIN_DIR:-/out/opt/kubeclaw/bin}"
TARGETARCH="${TARGETARCH:-amd64}"

mkdir -p "$OUT_BIN_DIR"

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

json_get() {
  key="$1"
  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const key = process.argv[2];
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    const value = key.split(".").reduce((acc, part) => (acc && Object.prototype.hasOwnProperty.call(acc, part) ? acc[part] : undefined), data);
    if (value === undefined) {
      process.exit(1);
    }
    process.stdout.write(String(value));
  ' "$PACKAGES_FILE" "$key"
}

map_arch() {
  case "$TARGETARCH" in
    amd64) echo "amd64" ;;
    arm64) echo "arm64" ;;
    *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;;
  esac
}

map_arch_uname() {
  case "$TARGETARCH" in
    amd64) echo "x86_64" ;;
    arm64) echo "arm64" ;;
    *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;;
  esac
}

map_arch_rust() {
  case "$TARGETARCH" in
    amd64) echo "x86_64" ;;
    arm64) echo "aarch64" ;;
    *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;;
  esac
}

render_url() {
  template="$1"
  version="$2"
  arch="$3"
  node -e '
    const tpl = process.argv[1];
    const version = process.argv[2];
    const arch = process.argv[3];
    process.stdout.write(tpl.replaceAll("{{version}}", version).replaceAll("{{arch}}", arch));
  ' "$template" "$version" "$arch"
}

github_asset_digest() {
  repo="$1"
  tag="$2"
  asset_name="$3"

  node -e '
    const https = require("https");
    const [repo, tag, assetName] = process.argv.slice(1);
    const url = `https://api.github.com/repos/${repo}/releases/tags/${tag}`;

    https.get(url, {
      headers: {
        "User-Agent": "kubeclaw-image-build",
        "Accept": "application/vnd.github+json"
      }
    }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        if (res.statusCode !== 200) {
          process.stderr.write(`failed to fetch ${url}: status ${res.statusCode}\n`);
          process.exit(1);
        }
        const data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        const asset = (data.assets || []).find((a) => a.name === assetName);
        if (!asset) {
          process.stderr.write(`asset ${assetName} not found in ${repo}@${tag}\n`);
          process.exit(1);
        }
        if (!asset.digest || !String(asset.digest).startsWith("sha256:")) {
          process.stderr.write(`asset ${assetName} missing sha256 digest in ${repo}@${tag}\n`);
          process.exit(1);
        }
        process.stdout.write(String(asset.digest).slice("sha256:".length));
      });
    }).on("error", (err) => {
      process.stderr.write(String(err.message) + "\n");
      process.exit(1);
    });
  ' "$repo" "$tag" "$asset_name"
}

verify_download() {
  file="$1"
  expected_sha="$2"
  actual_sha="$(sha256_file "$file")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "checksum verification failed for $file" >&2
    echo "expected: $expected_sha" >&2
    echo "actual:   $actual_sha" >&2
    exit 1
  fi
}

install_gh() {
  enabled="$(json_get 'cli.gh.enabled' || true)"
  [ "$enabled" = "true" ] || return 0
  version="$(json_get 'cli.gh.version')"
  tpl="$(json_get 'cli.gh.downloadUrlTemplate')"
  arch="$(map_arch)"
  url="$(render_url "$tpl" "$version" "$arch")"
  work="/tmp/gh"
  archive="gh_${version}_linux_${arch}.tar.gz"
  mkdir -p "$work"
  curl -fsSL "$url" -o "$work/$archive"
  expected_sha="$(github_asset_digest "cli/cli" "v${version}" "$archive")"
  verify_download "$work/$archive" "$expected_sha"
  tar xzf "$work/$archive" -C "$work"
  cp "$work/gh_${version}_linux_${arch}/bin/gh" "$OUT_BIN_DIR/gh"
  chmod 0555 "$OUT_BIN_DIR/gh"
}

install_jira() {
  enabled="$(json_get 'cli.jira.enabled' || true)"
  [ "$enabled" = "true" ] || return 0
  version="$(json_get 'cli.jira.version')"
  tpl="$(json_get 'cli.jira.downloadUrlTemplate')"
  arch="$(map_arch_uname)"
  url="$(render_url "$tpl" "$version" "$arch")"
  work="/tmp/jira"
  archive="jira_${version}_linux_${arch}.tar.gz"
  mkdir -p "$work"
  curl -fsSL "$url" -o "$work/$archive"
  expected_sha="$(github_asset_digest "ankitpokhrel/jira-cli" "v${version}" "$archive")"
  verify_download "$work/$archive" "$expected_sha"
  tar xzf "$work/$archive" -C "$work"
  if [ -x "$work/jira_${version}_linux_${arch}/bin/jira" ]; then
    cp "$work/jira_${version}_linux_${arch}/bin/jira" "$OUT_BIN_DIR/jira"
  elif [ -x "$work/bin/jira" ]; then
    cp "$work/bin/jira" "$OUT_BIN_DIR/jira"
  else
    echo "jira binary not found" >&2
    exit 1
  fi
  chmod 0555 "$OUT_BIN_DIR/jira"
}

install_linear() {
  enabled="$(json_get 'cli.linear.enabled' || true)"
  [ "$enabled" = "true" ] || return 0
  version="$(json_get 'cli.linear.version')"
  tpl="$(json_get 'cli.linear.downloadUrlTemplate')"
  arch="$(map_arch_rust)"
  url="$(render_url "$tpl" "$version" "$arch")"
  work="/tmp/linear"
  archive="linear-${arch}-unknown-linux-gnu.tar.xz"
  mkdir -p "$work"
  curl -fsSL "$url" -o "$work/$archive"
  expected_sha="$(github_asset_digest "schpet/linear-cli" "v${version}" "$archive")"
  verify_download "$work/$archive" "$expected_sha"
  tar xJf "$work/$archive" -C "$work"
  linear_bin="$(find "$work" -type f -name linear -perm -u+x | head -n 1)"
  if [ -z "$linear_bin" ]; then
    echo "linear binary not found" >&2
    exit 1
  fi
  cp "$linear_bin" "$OUT_BIN_DIR/linear"
  chmod 0555 "$OUT_BIN_DIR/linear"
}

install_asana() {
  enabled="$(json_get 'cli.asana.enabled' || true)"
  [ "$enabled" = "true" ] || return 0
  version="$(json_get 'cli.asana.version')"
  tpl="$(json_get 'cli.asana.downloadUrlTemplate')"
  arch="$(map_arch_uname)"
  url="$(render_url "$tpl" "$version" "$arch")"
  work="/tmp/asana"
  archive="asana_Linux_${arch}.tar.gz"
  mkdir -p "$work"
  curl -fsSL "$url" -o "$work/$archive"
  expected_sha="$(github_asset_digest "timwehrle/asana" "v${version}" "$archive")"
  verify_download "$work/$archive" "$expected_sha"
  tar xzf "$work/$archive" -C "$work"
  asana_bin="$(find "$work" -type f -name asana -perm -u+x | head -n 1)"
  if [ -z "$asana_bin" ]; then
    echo "asana binary not found" >&2
    exit 1
  fi
  cp "$asana_bin" "$OUT_BIN_DIR/asana"
  chmod 0555 "$OUT_BIN_DIR/asana"
}

install_trello() {
  enabled="$(json_get 'cli.trello.enabled' || true)"
  [ "$enabled" = "true" ] || return 0
  version="$(json_get 'cli.trello.version')"
  npm install --prefix /tmp/trello --cache /tmp/.npm "trello-cli@${version}" --no-save --no-audit --no-fund >/dev/null
  if [ -x /tmp/trello/node_modules/.bin/trello ]; then
    cp /tmp/trello/node_modules/.bin/trello "$OUT_BIN_DIR/trello"
  elif [ -x /tmp/trello/node_modules/trello-cli/bin/trello ]; then
    cp /tmp/trello/node_modules/trello-cli/bin/trello "$OUT_BIN_DIR/trello"
  else
    echo "trello binary not found" >&2
    exit 1
  fi
  chmod 0555 "$OUT_BIN_DIR/trello"
}

install_gh
install_jira
install_linear
install_asana
install_trello
