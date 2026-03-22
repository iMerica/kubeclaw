#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# KubeClaw CLI Installer
# curl -fsSL https://kubeclaw.ai/install-cli.sh | bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

REPO="iMerica/kubeclaw"
BINARY="kubeclaw"
INSTALL_DIR="/usr/local/bin"

# ── Detect OS and architecture ──────────────────────────────────────────────
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  linux|darwin) ;;
  *)
    echo "Error: Unsupported OS: $OS"
    exit 1
    ;;
esac

echo "Detected: ${OS}/${ARCH}"

# ── Fetch latest release ───────────────────────────────────────────────────
echo "Fetching latest release..."
LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [[ -z "$LATEST" ]]; then
  echo "Error: Could not determine latest release."
  exit 1
fi

VERSION="${LATEST#cli-}"
echo "Latest version: ${VERSION}"

# ── Download ────────────────────────────────────────────────────────────────
ARCHIVE="${BINARY}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${LATEST}/${ARCHIVE}"

echo "Downloading ${URL}..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL "$URL" -o "${TMPDIR}/${ARCHIVE}"

# ── Extract ─────────────────────────────────────────────────────────────────
echo "Extracting..."
tar -xzf "${TMPDIR}/${ARCHIVE}" -C "$TMPDIR"

# ── Install ─────────────────────────────────────────────────────────────────
if [[ -w "$INSTALL_DIR" ]]; then
  mv "${TMPDIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
else
  echo "Installing to ${INSTALL_DIR} (requires sudo)..."
  sudo mv "${TMPDIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
fi

chmod +x "${INSTALL_DIR}/${BINARY}"

# ── Verify ──────────────────────────────────────────────────────────────────
if command -v "$BINARY" &>/dev/null; then
  echo ""
  echo "Successfully installed kubeclaw!"
  "$BINARY" version
  echo ""
  echo "Get started:"
  echo "  kubeclaw install    Install KubeClaw on your cluster"
  echo "  kubeclaw --help     Show all commands"
else
  # Try ~/.local/bin as fallback
  FALLBACK_DIR="${HOME}/.local/bin"
  mkdir -p "$FALLBACK_DIR"
  cp "${INSTALL_DIR}/${BINARY}" "${FALLBACK_DIR}/${BINARY}" 2>/dev/null || true
  echo ""
  echo "Installed to ${INSTALL_DIR}/${BINARY}"
  echo "If the command is not found, add ${INSTALL_DIR} to your PATH."
fi
