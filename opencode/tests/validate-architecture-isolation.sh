#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test -d "$ROOT/verl-subagent-union-workflow/agents"
test -d "$ROOT/verl-subagent-union-workflow/skills"
test "$(find "$ROOT/verl-subagent-union-workflow/agents" -maxdepth 1 -type f -name '*.md' | wc -l)" -eq 12
test -s "$ROOT/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/SKILL.md"
test ! -e "$ROOT/.codex"
test ! -e "$ROOT/chatgpt"
(cd "$ROOT/versions/v1" && sha256sum -c SHA256SUMS)

if rg -n -i '(^|[/.])(codex|chatgpt)([/.]|$)|\.codex' "$ROOT" \
  --glob '!**/patches/*.patch' \
  --glob '!**/validate-architecture-isolation.sh' \
  --glob '!**/.omo/**'; then
  echo 'OpenCode architecture contains a ChatGPT/Codex runtime reference' >&2
  exit 1
fi

echo 'OpenCode architecture isolation passed'
