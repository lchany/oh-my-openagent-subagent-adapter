#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test -d "$ROOT/.codex/agents"
test -d "$ROOT/plugins"
test ! -e "$ROOT/.opencode"
test ! -e "$ROOT/opencode"

if rg -n -i '(^|[/.])opencode([/.]|$)|\.opencode|\.omo' "$ROOT" \
  --glob '!**/versions/**/*.patch' \
  --glob '!**/validate-architecture-isolation.sh'; then
  echo 'ChatGPT architecture contains an OpenCode runtime reference' >&2
  exit 1
fi

echo 'ChatGPT architecture isolation passed'
