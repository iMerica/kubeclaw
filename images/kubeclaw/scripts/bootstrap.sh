#!/bin/sh
set -eu

CONFIG_MODE="${KUBECLAW_CONFIG_MODE:-merge}"
SKILLSTACKS_ENABLED="${KUBECLAW_SKILLSTACKS_ENABLED:-true}"
SKILLS_WATCH="${KUBECLAW_SKILLS_WATCH:-true}"
SKILLS_NODE_MANAGER="${KUBECLAW_SKILLS_NODE_MANAGER:-npm}"
SKILLS_EXTRA_DIRS_JSON="${KUBECLAW_SKILLS_EXTRA_DIRS_JSON:-[]}"
SKILLSTACK_PLATFORM_ENGINEERING_ENABLED="${KUBECLAW_SKILLSTACK_PLATFORM_ENGINEERING_ENABLED:-true}"
SKILLSTACK_DEVOPS_ENABLED="${KUBECLAW_SKILLSTACK_DEVOPS_ENABLED:-true}"
SKILLSTACK_SRE_ENABLED="${KUBECLAW_SKILLSTACK_SRE_ENABLED:-true}"
SKILLSTACK_SWE_ENABLED="${KUBECLAW_SKILLSTACK_SWE_ENABLED:-true}"
SKILLSTACK_QA_ENABLED="${KUBECLAW_SKILLSTACK_QA_ENABLED:-true}"
SKILLSTACK_MARKETING_ENABLED="${KUBECLAW_SKILLSTACK_MARKETING_ENABLED:-true}"
STATE_DIR="/home/node/.openclaw"
CONFIG_DEST="$STATE_DIR/openclaw.json"
CONFIG_SRC="/config-src/openclaw.json"
SKILLS_DIR="$STATE_DIR/skills"
SKILLSTACKS_SRC_DIR="/opt/kubeclaw/skillstacks"
SKILLS_PATCH_JSON="$STATE_DIR/skills.generated.json"
MERGE_SCRIPT="/opt/kubeclaw/bin/merge-json5.js"
RENDER_SKILLS_SCRIPT="/opt/kubeclaw/bin/render-skills-config.js"

apply_desired_config() {
  if [ ! -f "$CONFIG_SRC" ]; then
    return
  fi

  if [ "$CONFIG_MODE" = "overwrite" ]; then
    cp "$CONFIG_SRC" "$CONFIG_DEST"
    return
  fi

  if [ ! -f "$CONFIG_DEST" ]; then
    cp "$CONFIG_SRC" "$CONFIG_DEST"
    return
  fi

  node "$MERGE_SCRIPT" "$CONFIG_DEST" "$CONFIG_SRC" > "$CONFIG_DEST.tmp"
  mv "$CONFIG_DEST.tmp" "$CONFIG_DEST"
}

install_skillstacks() {
  [ "$SKILLSTACKS_ENABLED" = "true" ] || return
  [ -d "$SKILLSTACKS_SRC_DIR" ] || return

  mkdir -p "$SKILLS_DIR"

  for domain_dir in "$SKILLSTACKS_SRC_DIR"/*; do
    [ -d "$domain_dir" ] || continue
    domain_name="$(basename "$domain_dir")"
    case "$domain_name" in
      platform-engineering) [ "$SKILLSTACK_PLATFORM_ENGINEERING_ENABLED" = "true" ] || continue ;;
      devops) [ "$SKILLSTACK_DEVOPS_ENABLED" = "true" ] || continue ;;
      sre) [ "$SKILLSTACK_SRE_ENABLED" = "true" ] || continue ;;
      swe) [ "$SKILLSTACK_SWE_ENABLED" = "true" ] || continue ;;
      qa) [ "$SKILLSTACK_QA_ENABLED" = "true" ] || continue ;;
      marketing) [ "$SKILLSTACK_MARKETING_ENABLED" = "true" ] || continue ;;
    esac

    for skill_dir in "$domain_dir"/*; do
      [ -d "$skill_dir" ] || continue
      if [ -f "$skill_dir/SKILL.md" ]; then
        skill_name="$(basename "$skill_dir")"
        mkdir -p "$SKILLS_DIR/$skill_name"
        cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
      fi
    done
  done

  node "$RENDER_SKILLS_SCRIPT" "$SKILLS_DIR" "$SKILLS_PATCH_JSON"
  if [ ! -f "$CONFIG_DEST" ]; then
    cp "$SKILLS_PATCH_JSON" "$CONFIG_DEST"
  else
    node "$MERGE_SCRIPT" "$CONFIG_DEST" "$SKILLS_PATCH_JSON" > "$CONFIG_DEST.tmp"
    mv "$CONFIG_DEST.tmp" "$CONFIG_DEST"
  fi
}

main() {
  mkdir -p "$STATE_DIR"
  export KUBECLAW_SKILLS_WATCH="$SKILLS_WATCH"
  export KUBECLAW_SKILLS_NODE_MANAGER="$SKILLS_NODE_MANAGER"
  export KUBECLAW_SKILLS_EXTRA_DIRS_JSON="$SKILLS_EXTRA_DIRS_JSON"
  apply_desired_config
  install_skillstacks
  exec "$@"
}

main "$@"
