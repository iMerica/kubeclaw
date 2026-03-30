#!/usr/bin/env bash
set -euo pipefail

shopt -s globstar nullglob

skill_files=(charts/kubeclaw/skillstacks/**/SKILL.md)

if [[ ${#skill_files[@]} -eq 0 ]]; then
  echo "No SkillStack SKILL.md files found under charts/kubeclaw/skillstacks" >&2
  exit 1
fi

failed=0

for file in "${skill_files[@]}"; do
  if awk '
    NR == 1 {
      if ($0 != "---") exit 2
      in_frontmatter = 1
      next
    }

    in_frontmatter == 1 {
      if ($0 == "---") {
        has_end = 1
        exit 0
      }
      if ($0 ~ /^name:[[:space:]]*[^[:space:]]/) has_name = 1
      if ($0 ~ /^description:[[:space:]]*[^[:space:]]/) has_description = 1
    }

    END {
      if (NR == 0) exit 2
      if (!has_end) exit 3
      if (!has_name) exit 4
      if (!has_description) exit 5
    }
  ' "$file"; then
    continue
  else
    status=$?
    failed=1
    case "$status" in
      2) echo "FAIL: $file is missing opening frontmatter delimiter (---)" >&2 ;;
      3) echo "FAIL: $file is missing closing frontmatter delimiter (---)" >&2 ;;
      4) echo "FAIL: $file frontmatter is missing required 'name'" >&2 ;;
      5) echo "FAIL: $file frontmatter is missing required 'description'" >&2 ;;
      *) echo "FAIL: $file frontmatter validation failed" >&2 ;;
    esac
  fi
done

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo "PASS: SkillStack SKILL.md frontmatter is valid"
