#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# KubeClaw Installer
# curl -fsSL https://kubeclaw.ai/install.sh | bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

# ── OCI chart reference ──────────────────────────────────────────────────────
CHART_REF="oci://ghcr.io/imerica/kubeclaw"

# ── Color palette ─────────────────────────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RESET=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  CYAN=$(tput setaf 6)
  WHITE=$(tput setaf 7)
else
  BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" CYAN="" WHITE=""
fi

# ── Terminal width ────────────────────────────────────────────────────────────
COLS=$(tput cols 2>/dev/null || echo 80)
[[ $COLS -gt 100 ]] && COLS=100

# ── Status badges ─────────────────────────────────────────────────────────────
badge_ok()   { printf "%s[  OK  ]%s" "${GREEN}" "${RESET}"; }
badge_skip() { printf "%s[ SKIP ]%s" "${YELLOW}" "${RESET}"; }
badge_fail() { printf "%s[ FAIL ]%s" "${RED}" "${RESET}"; }
badge_wait() { printf "%s[ .... ]%s" "${DIM}" "${RESET}"; }

# ── Drawing helpers ───────────────────────────────────────────────────────────
hr()       { printf "%s%s%s\n" "${CYAN}" "$(printf '━%.0s' $(seq 1 "$COLS"))" "${RESET}"; }
section()  { printf "\n%s┃%s %s%s%s\n" "${CYAN}" "${RESET}" "${BOLD}${WHITE}" "$1" "${RESET}"; hr; }
info()     { printf "  %s▸%s %s\n" "${CYAN}" "${RESET}" "$1"; }
hint()     { printf "  %s%s%s\n" "${DIM}" "$1" "${RESET}"; }
success()  { printf "  %s✔ %s%s\n" "${GREEN}" "$1" "${RESET}"; }
warn()     { printf "  %s⚠ %s%s\n" "${YELLOW}" "$1" "${RESET}"; }
err()      { printf "  %s✘ %s%s\n" "${RED}" "$1" "${RESET}"; }
die()      { err "$1"; exit 1; }

# ── Spinner ───────────────────────────────────────────────────────────────────
SPINNER_PID=""
spinner_start() {
  local msg="$1"
  (
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while true; do
      printf "\r  %s%s%s %s" "${CYAN}" "${frames[$i]}" "${RESET}" "$msg"
      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
  if [[ -n "${SPINNER_PID}" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf "\r%${COLS}s\r" ""
  fi
}

cleanup() {
  spinner_stop
}
trap cleanup EXIT

# ── Interactive detection ─────────────────────────────────────────────────────
INTERACTIVE=true
if [[ ! -t 0 ]]; then
  # stdin is a pipe (curl | bash) — reopen from tty if available
  if [[ -e /dev/tty ]]; then
    exec </dev/tty
  else
    INTERACTIVE=false
  fi
fi

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

# ── Prompt helper ─────────────────────────────────────────────────────────────
# Usage: prompt "Question" "default_value" VARIABLE
prompt() {
  local question="$1" default="$2" varname="$3"
  if [[ "$INTERACTIVE" == true ]]; then
    local display_default=""
    [[ -n "$default" ]] && display_default=" ${DIM}[${default}]${RESET}"
    printf "  %s›%s %s%s: " "${CYAN}" "${RESET}" "$question" "$display_default"
    local answer
    read -r answer
    answer="${answer:-$default}"
    eval "$varname=\"\$answer\""
  else
    eval "$varname=\"\$default\""
  fi
}

# Usage: prompt_secret "Question" VARIABLE
prompt_secret() {
  local question="$1" varname="$2"
  if [[ "$INTERACTIVE" == true ]]; then
    printf "  %s›%s %s: " "${CYAN}" "${RESET}" "$question"
    local answer
    read -rs answer
    echo ""
    eval "$varname=\"\$answer\""
  else
    eval "$varname=\"\""
  fi
}

# Usage: prompt_yn "Question?" default(y/n) VARIABLE → sets to "true"/"false"
prompt_yn() {
  local question="$1" default="$2" varname="$3"
  if [[ "$INTERACTIVE" == true ]]; then
    local yn_hint="y/n"
    [[ "$default" == "y" ]] && yn_hint="Y/n"
    [[ "$default" == "n" ]] && yn_hint="y/N"
    printf "  %s›%s %s ${DIM}[%s]${RESET}: " "${CYAN}" "${RESET}" "$question" "$yn_hint"
    local answer
    read -r answer
    answer="${answer:-$default}"
    case "$answer" in
      [Yy]*) eval "$varname=true" ;;
      *)     eval "$varname=false" ;;
    esac
  else
    case "$default" in
      [Yy]*) eval "$varname=true" ;;
      *)     eval "$varname=false" ;;
    esac
  fi
}

# Usage: prompt_choice "Question" VARIABLE opt1 opt2 opt3...
prompt_choice() {
  local question="$1" varname="$2"
  shift 2
  local options=("$@")
  if [[ "$INTERACTIVE" == true ]]; then
    printf "  %s›%s %s\n" "${CYAN}" "${RESET}" "$question"
    local i=1
    for opt in "${options[@]}"; do
      printf "    %s%d)%s %s\n" "${CYAN}" "$i" "${RESET}" "$opt"
      i=$((i + 1))
    done
    printf "  %s›%s Choice ${DIM}[1]${RESET}: " "${CYAN}" "${RESET}"
    local answer
    read -r answer
    answer="${answer:-1}"
    if [[ "$answer" =~ ^[0-9]+$ ]] && [[ "$answer" -ge 1 ]] && [[ "$answer" -le ${#options[@]} ]]; then
      eval "$varname=\"\${options[$((answer - 1))]}\""
    else
      eval "$varname=\"\${options[0]}\""
    fi
  else
    eval "$varname=\"\${options[0]}\""
  fi
}

# ── Logo ──────────────────────────────────────────────────────────────────────
show_logo() {
  printf "\n"
  cat <<'LOGO'
         ██╗  ██╗██╗   ██╗██████╗ ███████╗ ██████╗██╗      █████╗ ██╗    ██╗
         ██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔════╝██║     ██╔══██╗██║    ██║
         █████╔╝ ██║   ██║██████╔╝█████╗  ██║     ██║     ███████║██║ █╗ ██║
         ██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██║     ██║     ██╔══██║██║███╗██║
         ██║  ██╗╚██████╔╝██████╔╝███████╗╚██████╗███████╗██║  ██║╚███╔███╔╝
         ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
LOGO
  printf "  %s%sRun OpenClaw on Kubernetes with built-in guardrails%s\n" "${DIM}" "${WHITE}" "${RESET}"
  printf "  %s%shttps://kubeclaw.ai%s\n\n" "${DIM}" "${CYAN}" "${RESET}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. Logo + welcome
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
show_logo
hr
printf "  %sThis installer will walk you through deploying KubeClaw on your cluster.%s\n" "${WHITE}" "${RESET}"
printf "  %sNo files are written to disk — all secrets are passed via --set flags.%s\n" "${DIM}" "${RESET}"
hr

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. Preflight checks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Preflight Checks"

# kubectl
if command -v kubectl &>/dev/null; then
  KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
  printf "  %s kubectl %s\n" "$(badge_ok)" "$KUBECTL_VERSION"
else
  printf "  %s kubectl not found\n" "$(badge_fail)"
  die "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
fi

# helm
if command -v helm &>/dev/null; then
  HELM_VERSION=$(helm version --short 2>/dev/null | head -1)
  HELM_MAJOR=""
  if [[ "$HELM_VERSION" =~ ^v([0-9]+)\..* ]]; then
    HELM_MAJOR="${BASH_REMATCH[1]}"
  fi

  if [[ -n "$HELM_MAJOR" ]] && (( HELM_MAJOR >= 3 )); then
    printf "  %s helm %s\n" "$(badge_ok)" "$HELM_VERSION"
  else
    printf "  %s helm 3+ required (found %s)\n" "$(badge_fail)" "${HELM_VERSION:-unknown}"
    die "Install Helm (v3 or newer): https://helm.sh/docs/intro/install/"
  fi
else
  printf "  %s helm not found\n" "$(badge_fail)"
  die "Install Helm (v3 or newer): https://helm.sh/docs/intro/install/"
fi

# openssl (for key generation)
if command -v openssl &>/dev/null; then
  printf "  $(badge_ok) openssl\n"
  HAS_OPENSSL=true
else
  printf "  $(badge_skip) openssl not found — auto-generation disabled\n"
  HAS_OPENSSL=false
fi

# cluster reachable
if kubectl cluster-info &>/dev/null 2>&1; then
  printf "  $(badge_ok) cluster reachable\n"
else
  printf "  $(badge_fail) cannot reach Kubernetes cluster\n"
  die "Check your kubeconfig and cluster connectivity."
fi

# current context
KUBE_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
KUBE_CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$KUBE_CONTEXT')].context.cluster}" 2>/dev/null || echo "")
info "Context: ${BOLD}${KUBE_CONTEXT}${RESET}"
[[ -n "$KUBE_CLUSTER" ]] && info "Cluster: ${BOLD}${KUBE_CLUSTER}${RESET}"

if [[ "$INTERACTIVE" == true ]]; then
  prompt_yn "Is this the correct cluster?" "y" CONFIRM_CLUSTER
  [[ "$CONFIRM_CLUSTER" != "true" ]] && die "Switch to the correct context with: kubectl config use-context <name>"
fi

# storage classes
STORAGE_CLASSES=$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$STORAGE_CLASSES" ]]; then
  printf "  $(badge_ok) storage classes: %s\n" "$STORAGE_CLASSES"
  [[ -n "$DEFAULT_SC" ]] && info "Default: ${BOLD}${DEFAULT_SC}${RESET}"
else
  printf "  $(badge_skip) no storage classes found — PVCs may fail\n"
  warn "Ensure your cluster has a default StorageClass or specify one during setup."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. Namespace + Release Name
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Installation Settings"

NAMESPACE="${NAMESPACE:-kubeclaw}"
RELEASE="${RELEASE:-kubeclaw}"

prompt "Namespace" "$NAMESPACE" NAMESPACE
prompt "Release name" "$RELEASE" RELEASE

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. LLM Provider
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "LLM Provider"
hint "KubeClaw routes all LLM calls through a built-in LiteLLM proxy."
hint "You need at least one provider API key."
echo ""

LLM_PROVIDER=""
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

prompt_choice "Which LLM provider?" LLM_PROVIDER "OpenAI" "Anthropic" "OpenRouter" "Skip (configure later)"

case "$LLM_PROVIDER" in
  "OpenAI")
    if [[ -z "$OPENAI_API_KEY" ]]; then
      prompt_secret "OpenAI API key (sk-...)" OPENAI_API_KEY
    else
      info "Using OPENAI_API_KEY from environment"
    fi
    [[ -z "$OPENAI_API_KEY" ]] && die "OpenAI API key is required."
    ;;
  "Anthropic")
    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
      prompt_secret "Anthropic API key (sk-ant-...)" ANTHROPIC_API_KEY
    else
      info "Using ANTHROPIC_API_KEY from environment"
    fi
    [[ -z "$ANTHROPIC_API_KEY" ]] && die "Anthropic API key is required."
    ;;
  "OpenRouter")
    if [[ -z "$OPENROUTER_API_KEY" ]]; then
      prompt_secret "OpenRouter API key (sk-or-...)" OPENROUTER_API_KEY
    else
      info "Using OPENROUTER_API_KEY from environment"
    fi
    [[ -z "$OPENROUTER_API_KEY" ]] && die "OpenRouter API key is required."
    ;;
  *)
    warn "Skipping LLM provider — you'll need to configure one after install."
    ;;
esac

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. Gateway Token
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Gateway Token"
hint "The Gateway requires an auth token for health probes and API access."

OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

if [[ -n "$OPENCLAW_GATEWAY_TOKEN" ]]; then
  info "Using OPENCLAW_GATEWAY_TOKEN from environment"
elif [[ "$HAS_OPENSSL" == true ]]; then
  prompt_yn "Auto-generate a secure token?" "y" AUTO_GEN_TOKEN
  if [[ "$AUTO_GEN_TOKEN" == true ]]; then
    OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    success "Generated token: ${DIM}${OPENCLAW_GATEWAY_TOKEN:0:16}...${RESET}"
  else
    prompt_secret "Paste your gateway token" OPENCLAW_GATEWAY_TOKEN
  fi
else
  prompt_secret "Paste your gateway token" OPENCLAW_GATEWAY_TOKEN
fi
[[ -z "$OPENCLAW_GATEWAY_TOKEN" ]] && die "Gateway token is required."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. LiteLLM Master Key
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "LiteLLM Master Key"
hint "The LiteLLM proxy requires a master key (must start with 'sk-')."

LITELLM_MASTERKEY="${LITELLM_MASTERKEY:-}"

if [[ -n "$LITELLM_MASTERKEY" ]]; then
  info "Using LITELLM_MASTERKEY from environment"
elif [[ "$HAS_OPENSSL" == true ]]; then
  prompt_yn "Auto-generate a master key?" "y" AUTO_GEN_LITELLM
  if [[ "$AUTO_GEN_LITELLM" == true ]]; then
    LITELLM_MASTERKEY="sk-$(openssl rand -hex 16)"
    success "Generated key: ${DIM}${LITELLM_MASTERKEY:0:12}...${RESET}"
  else
    prompt_secret "Paste your LiteLLM master key (sk-...)" LITELLM_MASTERKEY
  fi
else
  prompt_secret "Paste your LiteLLM master key (sk-...)" LITELLM_MASTERKEY
fi
[[ -z "$LITELLM_MASTERKEY" ]] && die "LiteLLM master key is required."
[[ "$LITELLM_MASTERKEY" != sk-* ]] && die "LiteLLM master key must start with 'sk-'."

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. Tailscale
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Tailscale Integration"
hint "Tailscale provides SSH access and tailnet exposure for your Gateway."

TS_AUTHKEY="${TS_AUTHKEY:-${TAILSCALE_AUTH_KEY:-}}"
TAILSCALE_ENABLED=false

if [[ -n "$TS_AUTHKEY" ]]; then
  info "Using TS_AUTHKEY from environment"
  TAILSCALE_ENABLED=true
else
  prompt_yn "Enable Tailscale SSH + tailnet exposure?" "y" TAILSCALE_ENABLED
  if [[ "$TAILSCALE_ENABLED" == true ]]; then
    prompt_secret "Tailscale auth key (tskey-auth-...)" TS_AUTHKEY
    [[ -z "$TS_AUTHKEY" ]] && die "Tailscale auth key is required when Tailscale is enabled."
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. Obsidian Vault
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Obsidian Vault"
hint "KubeClaw can provision a persistent Markdown vault for the Obsidian skill."

OBSIDIAN_ENABLED=true
OBSIDIAN_SIZE="5Gi"

prompt_yn "Enable Obsidian vault?" "y" OBSIDIAN_ENABLED
if [[ "$OBSIDIAN_ENABLED" == true ]]; then
  prompt "Vault size" "$OBSIDIAN_SIZE" OBSIDIAN_SIZE
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. Storage Class
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Storage"

STORAGE_CLASS=""
if [[ -n "$STORAGE_CLASSES" ]]; then
  SC_ARRAY=()
  for sc in $STORAGE_CLASSES; do
    SC_ARRAY+=("$sc")
  done
  SC_ARRAY+=("(cluster default)")
  prompt_choice "Storage class for PVCs?" STORAGE_CLASS "${SC_ARRAY[@]}"
  [[ "$STORAGE_CLASS" == "(cluster default)" ]] && STORAGE_CLASS=""
else
  info "No storage classes detected — using cluster default."
fi

PERSISTENCE_SIZE="5Gi"
prompt "OpenClaw storage volume size" "$PERSISTENCE_SIZE" PERSISTENCE_SIZE

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. Review Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Review"

# Table helper
row() {
  printf "  %s%-24s%s %s\n" "${DIM}" "$1" "${RESET}" "$2"
}

row "Namespace:" "$NAMESPACE"
row "Release:" "$RELEASE"
row "Chart:" "$CHART_REF"
row "LLM Provider:" "${LLM_PROVIDER:-none}"
row "Gateway Token:" "${OPENCLAW_GATEWAY_TOKEN:0:12}..."
row "LiteLLM Key:" "${LITELLM_MASTERKEY:0:12}..."
row "Tailscale:" "$( [[ "$TAILSCALE_ENABLED" == true ]] && echo "enabled" || echo "disabled" )"
row "Obsidian Vault:" "$( [[ "$OBSIDIAN_ENABLED" == true ]] && echo "enabled (${OBSIDIAN_SIZE})" || echo "disabled" )"
row "Storage Class:" "${STORAGE_CLASS:-cluster default}"
row "OpenClaw Storage:" "$PERSISTENCE_SIZE"
echo ""

if [[ "$INTERACTIVE" == true ]]; then
  prompt_yn "Proceed with installation?" "y" CONFIRM_INSTALL
  [[ "$CONFIRM_INSTALL" != "true" ]] && die "Installation cancelled."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. Build Helm args
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HELM_SETS=(
  --set "secret.create=true"
  --set "secret.data.OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
  --set "litellm.masterkey=${LITELLM_MASTERKEY}"
  --set "persistence.size=${PERSISTENCE_SIZE}"
)

# Storage class
if [[ -n "$STORAGE_CLASS" ]]; then
  HELM_SETS+=(--set "persistence.storageClass=${STORAGE_CLASS}")
fi

# LLM provider keys
if [[ -n "$OPENAI_API_KEY" ]]; then
  HELM_SETS+=(--set "secret.data.OPENAI_API_KEY=${OPENAI_API_KEY}")
fi
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
  HELM_SETS+=(--set "secret.data.ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
fi
if [[ -n "$OPENROUTER_API_KEY" ]]; then
  HELM_SETS+=(--set "secret.data.OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
fi

# Tailscale
if [[ "$TAILSCALE_ENABLED" == true ]]; then
  HELM_SETS+=(--set "tailscale.ssh.authKey=${TS_AUTHKEY}")
else
  HELM_SETS+=(
    --set "tailscale.ssh.enabled=false"
    --set "tailscale.expose.enabled=false"
  )
fi

# Obsidian
if [[ "$OBSIDIAN_ENABLED" != true ]]; then
  HELM_SETS+=(--set "obsidian.enabled=false")
else
  HELM_SETS+=(--set "obsidian.persistence.size=${OBSIDIAN_SIZE}")
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. Install
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Installing KubeClaw"

# Create namespace if needed
if ! kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
  info "Creating namespace '$NAMESPACE'..."
  if [[ "$DRY_RUN" == true ]]; then
    success "Would create namespace $NAMESPACE (dry run)"
  else
    kubectl create namespace "$NAMESPACE"
    success "Namespace created"
  fi
else
  success "Namespace '$NAMESPACE' exists"
fi

# Helm install
HELM_CMD=(helm upgrade --install "$RELEASE" "$CHART_REF"
  --namespace "$NAMESPACE"
  "${HELM_SETS[@]}"
  --wait
  --timeout 10m
)

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  info "Dry-run mode — helm command that would run:"
  echo ""
  # Print command with secrets redacted
  REDACTED_CMD="${HELM_CMD[*]}"
  REDACTED_CMD=$(echo "$REDACTED_CMD" | sed -E 's/(OPENCLAW_GATEWAY_TOKEN=)[^ ]*/\1****/g')
  REDACTED_CMD=$(echo "$REDACTED_CMD" | sed -E 's/(masterkey=)[^ ]*/\1****/g')
  REDACTED_CMD=$(echo "$REDACTED_CMD" | sed -E 's/(API_KEY=)[^ ]*/\1****/g')
  REDACTED_CMD=$(echo "$REDACTED_CMD" | sed -E 's/(authKey=)[^ ]*/\1****/g')
  printf "  %s%s%s\n" "${DIM}" "$REDACTED_CMD" "${RESET}"
  echo ""
  success "Dry run complete — no changes were made."
  exit 0
fi

spinner_start "Installing KubeClaw (this may take a few minutes)..."

HELM_OUTPUT=""
HELM_EXIT=0
HELM_OUTPUT=$(eval "${HELM_CMD[@]}" 2>&1) || HELM_EXIT=$?

spinner_stop

if [[ $HELM_EXIT -ne 0 ]]; then
  err "Helm install failed (exit code $HELM_EXIT)"
  echo ""
  printf "%s\n" "$HELM_OUTPUT"
  echo ""
  die "Fix the errors above and re-run the installer."
fi

success "Helm release '$RELEASE' installed"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 13. Post-install
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
section "Post-Install"

# Show pods
info "Pods:"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" --no-headers 2>/dev/null | while read -r line; do
  printf "    %s\n" "$line"
done

echo ""

# Wait for Gateway ready
spinner_start "Waiting for Gateway pod to become ready..."

GATEWAY_READY=false
for i in $(seq 1 60); do
  STATUS=$(kubectl get pod "${RELEASE}-gateway-0" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$STATUS" == "True" ]]; then
    GATEWAY_READY=true
    break
  fi
  sleep 2
done

spinner_stop

if [[ "$GATEWAY_READY" == true ]]; then
  success "Gateway pod is ready"
else
  warn "Gateway pod not ready yet — it may still be starting."
  hint "Check status with: kubectl get pods -n $NAMESPACE"
fi

# Retrieve dashboard URL
DASHBOARD_URL=""
if [[ "$GATEWAY_READY" == true ]]; then
  spinner_start "Retrieving dashboard URL..."
  for i in $(seq 1 15); do
    URL=$(kubectl -n "$NAMESPACE" exec "${RELEASE}-gateway-0" -c gateway -- \
      node dist/index.js dashboard --no-open 2>/dev/null | grep "Dashboard URL:" || true)
    if [[ -n "$URL" ]]; then
      DASHBOARD_URL="${URL#*Dashboard URL: }"
      break
    fi
    sleep 2
  done
  spinner_stop
fi

# Port-forward offer
echo ""
LOCAL_PORT="${LOCAL_PORT:-18789}"

if [[ "$INTERACTIVE" == true ]]; then
  prompt_yn "Start port-forward for local access?" "y" DO_PORT_FORWARD
else
  DO_PORT_FORWARD=true
fi

if [[ "$DO_PORT_FORWARD" == true ]]; then
  info "Starting port-forward (localhost:${LOCAL_PORT} → ${RELEASE}-gateway:18789)..."
  kubectl port-forward -n "$NAMESPACE" "svc/${RELEASE}-gateway" "${LOCAL_PORT}:18789" &>/dev/null &
  PF_PID=$!
  sleep 2

  if kill -0 "$PF_PID" 2>/dev/null; then
    success "Port-forward running (PID ${PF_PID})"

    if [[ -n "$DASHBOARD_URL" ]]; then
      LOCAL_URL=$(echo "$DASHBOARD_URL" | sed "s|http://[^/]*|http://localhost:${LOCAL_PORT}|")
      echo ""
      printf "  %s┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓%s\n" "${GREEN}" "${RESET}"
      printf "  %s┃%s  Open in your browser:                                     %s┃%s\n" "${GREEN}" "${RESET}" "${GREEN}" "${RESET}"
      printf "  %s┃%s  %s%-56s%s %s┃%s\n" "${GREEN}" "${RESET}" "${BOLD}${CYAN}" "$LOCAL_URL" "${RESET}" "${GREEN}" "${RESET}"
      printf "  %s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛%s\n" "${GREEN}" "${RESET}"
    fi

    echo ""
    hint "Stop port-forward: kill $PF_PID"
  else
    warn "Port-forward failed. Start manually:"
    hint "kubectl port-forward -n $NAMESPACE svc/${RELEASE}-gateway ${LOCAL_PORT}:18789"
  fi
fi

# Next steps
echo ""
section "Next Steps"
info "View logs:       kubectl logs -n $NAMESPACE ${RELEASE}-gateway-0 -c gateway -f"
info "Shell access:    kubectl exec -n $NAMESPACE -it ${RELEASE}-gateway-0 -c gateway -- sh"
if [[ "$TAILSCALE_ENABLED" == true ]]; then
  info "SSH access:      ssh ${RELEASE}-gateway (once Tailscale connects)"
fi
info "Uninstall:       helm uninstall $RELEASE -n $NAMESPACE"
info "Documentation:   https://docs.kubeclaw.ai"
echo ""
hr
printf "  %s%sKubeClaw is ready. Happy building! 🦞%s\n" "${BOLD}" "${GREEN}" "${RESET}"
hr
echo ""
