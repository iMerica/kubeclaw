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
SKILLS_MANAGED_FILE="$STATE_DIR/skills.managed.txt"
SKILLS_MANAGED_PREV_FILE="$STATE_DIR/skills.managed.prev.txt"
MERGE_SCRIPT="/opt/kubeclaw/bin/merge-json5.js"
RENDER_SKILLS_SCRIPT="/opt/kubeclaw/bin/render-skills-config.js"

safe_skill_name() {
  case "$1" in
    ""|.*|*/*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

remove_managed_skills() {
  [ -f "$SKILLS_MANAGED_FILE" ] || return
  cp "$SKILLS_MANAGED_FILE" "$SKILLS_MANAGED_PREV_FILE"
  while IFS= read -r skill_name; do
    safe_skill_name "$skill_name" || continue
    rm -rf "${SKILLS_DIR:?}/${skill_name:?}"
  done < "$SKILLS_MANAGED_FILE"
}

merge_skills_config() {
  node "$RENDER_SKILLS_SCRIPT" "$SKILLS_DIR" "$SKILLS_PATCH_JSON" "$SKILLS_MANAGED_PREV_FILE"
  if [ ! -f "$CONFIG_DEST" ]; then
    cp "$SKILLS_PATCH_JSON" "$CONFIG_DEST"
  else
    node "$MERGE_SCRIPT" "$CONFIG_DEST" "$SKILLS_PATCH_JSON" > "$CONFIG_DEST.tmp"
    mv "$CONFIG_DEST.tmp" "$CONFIG_DEST"
  fi
}

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
  mkdir -p "$SKILLS_DIR"

  if [ -f "$SKILLS_MANAGED_FILE" ]; then
    remove_managed_skills
  else
    : > "$SKILLS_MANAGED_PREV_FILE"
  fi

  if [ "$SKILLSTACKS_ENABLED" != "true" ] || [ ! -d "$SKILLSTACKS_SRC_DIR" ]; then
    : > "$SKILLS_MANAGED_FILE"
    merge_skills_config
    return
  fi

  managed_tmp="$(mktemp "$STATE_DIR/skills-managed.XXXXXX")"

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
        safe_skill_name "$skill_name" || continue
        mkdir -p "$SKILLS_DIR/$skill_name"
        cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
        printf '%s\n' "$skill_name" >> "$managed_tmp"
      fi
    done
  done

  if [ -s "$managed_tmp" ]; then
    sort -u "$managed_tmp" > "$SKILLS_MANAGED_FILE"
  else
    : > "$SKILLS_MANAGED_FILE"
  fi
  rm -f "$managed_tmp"

  merge_skills_config
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
