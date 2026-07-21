#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PARENT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_PARENT"' EXIT
FIXTURE_ROOT="$FIXTURE_PARENT/chatgpt"
cp -a "$ROOT" "$FIXTURE_ROOT"
mv "$FIXTURE_ROOT/.codex/agents/baseline_runner.toml" "$FIXTURE_ROOT/.codex/agents/baseline_runner.toml.missing"

if "$FIXTURE_ROOT/scripts/audit_codex_workflow.sh" --no-tests > "$FIXTURE_PARENT/audit.out" 2>&1; then
  echo 'audit unexpectedly accepted an incomplete old environment' >&2
  exit 1
fi

rg -Fq 'MISMATCH expected five custom agents, found 4' "$FIXTURE_PARENT/audit.out"
rg -Fq 'MISSING custom agent file:' "$FIXTURE_PARENT/audit.out"
rg -Fq 'MISMATCH Codex marketplace points to' "$FIXTURE_PARENT/audit.out"
rg -Fq 'MISMATCH installed plugin source points to' "$FIXTURE_PARENT/audit.out"
rg -Fq 'NOT READY:' "$FIXTURE_PARENT/audit.out"

echo 'Codex workflow audit negative-path test passed'
