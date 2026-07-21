#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TESTS=true
if [[ "${1-}" == "--no-tests" ]]; then
  RUN_TESTS=false
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--no-tests]" >&2
  exit 64
fi

MARKETPLACE_FILE="$ROOT/.agents/plugins/marketplace.json"
PLUGIN_ROOT="$ROOT/plugins/verl-subagent-union-workflow"
PLUGIN_MANIFEST="$PLUGIN_ROOT/.codex-plugin/plugin.json"
AGENT_ROOT="$ROOT/.codex/agents"
CODEX_STATE_ROOT="${CODEX_HOME:-${HOME}/.codex}"
FAILURES=0

pass() { printf 'PASS    %s\n' "$1"; }
missing() { printf 'MISSING %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
mismatch() { printf 'MISMATCH %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
info() { printf 'INFO    %s\n' "$1"; }

printf 'Codex workflow audit\nroot: %s\n\n' "$ROOT"

for command_name in codex git python3 bash rg sha256sum diff; do
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "command available: $command_name"
  else
    missing "command unavailable: $command_name"
  fi
done

if [[ -d "$ROOT/.codex" && -d "$ROOT/plugins" && -d "$ROOT/tests" && -d "$ROOT/versions" ]]; then
  pass "ChatGPT architecture directories exist"
else
  missing "one or more architecture directories are absent: .codex plugins tests versions"
fi
if [[ -e "$ROOT/.opencode" || -e "$ROOT/opencode" ]]; then
  mismatch "OpenCode runtime files exist inside the ChatGPT architecture"
else
  pass "no OpenCode runtime root inside ChatGPT architecture"
fi

EXPECTED_AGENTS=(baseline_runner benchmark_comparator experiment_reporter optimized_runner workflow_supervisor)
if [[ -d "$AGENT_ROOT" ]]; then
  ACTUAL_AGENT_COUNT="$(find "$AGENT_ROOT" -maxdepth 1 -type f -name '*.toml' | wc -l)"
  if [[ "$ACTUAL_AGENT_COUNT" -eq "${#EXPECTED_AGENTS[@]}" ]]; then
    pass "exactly five project-scoped custom agents exist"
  else
    mismatch "expected five custom agents, found $ACTUAL_AGENT_COUNT"
  fi
  for role in "${EXPECTED_AGENTS[@]}"; do
    role_file="$AGENT_ROOT/$role.toml"
    if [[ ! -s "$role_file" ]]; then
      missing "custom agent file: $role_file"
      continue
    fi
    if rg -Fq "name = \"$role\"" "$role_file" \
      && rg -Fq 'description = ' "$role_file" \
      && rg -Fq 'developer_instructions = ' "$role_file"; then
      pass "custom agent schema markers: $role"
    else
      mismatch "custom agent required fields: $role"
    fi
  done
else
  missing "custom agent directory: $AGENT_ROOT"
fi

PLUGIN_METADATA=""
if [[ -s "$PLUGIN_MANIFEST" ]]; then
  if PLUGIN_METADATA="$(python3 - "$PLUGIN_MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)
required = ("name", "version", "description", "skills")
if any(not manifest.get(key) for key in required):
    raise SystemExit(2)
print(manifest["name"])
print(manifest["version"])
PY
  )"; then
    pass "plugin manifest is valid JSON with required fields"
  else
    mismatch "plugin manifest is invalid: $PLUGIN_MANIFEST"
  fi
else
  missing "plugin manifest: $PLUGIN_MANIFEST"
fi

PLUGIN_NAME="$(printf '%s\n' "$PLUGIN_METADATA" | sed -n '1p')"
PLUGIN_VERSION="$(printf '%s\n' "$PLUGIN_METADATA" | sed -n '2p')"
MARKETPLACE_METADATA=""
if [[ -s "$MARKETPLACE_FILE" ]]; then
  if MARKETPLACE_METADATA="$(python3 - "$MARKETPLACE_FILE" "$ROOT" "$PLUGIN_NAME" <<'PY'
import json
import os
import sys

path, root, plugin_name = sys.argv[1:]
with open(path, encoding="utf-8") as marketplace_file:
    marketplace = json.load(marketplace_file)
matches = [item for item in marketplace.get("plugins", []) if item.get("name") == plugin_name]
if len(matches) != 1:
    raise SystemExit(2)
source = matches[0].get("source", {})
source_path = source.get("path")
if source.get("source") != "local" or not isinstance(source_path, str):
    raise SystemExit(2)
resolved = os.path.realpath(os.path.join(root, source_path))
print(marketplace.get("name", ""))
print(resolved)
PY
  )"; then
    pass "marketplace JSON contains one local plugin entry"
  else
    mismatch "marketplace entry is invalid: $MARKETPLACE_FILE"
  fi
else
  missing "marketplace file: $MARKETPLACE_FILE"
fi

MARKETPLACE_NAME="$(printf '%s\n' "$MARKETPLACE_METADATA" | sed -n '1p')"
MARKETPLACE_PLUGIN_ROOT="$(printf '%s\n' "$MARKETPLACE_METADATA" | sed -n '2p')"
if [[ -n "$MARKETPLACE_PLUGIN_ROOT" && "$MARKETPLACE_PLUGIN_ROOT" == "$(realpath "$PLUGIN_ROOT" 2>/dev/null)" ]]; then
  pass "marketplace source resolves to the ChatGPT plugin directory"
elif [[ -n "$MARKETPLACE_PLUGIN_ROOT" ]]; then
  mismatch "marketplace source resolves to $MARKETPLACE_PLUGIN_ROOT"
fi

MARKETPLACE_LIST=""
if command -v codex >/dev/null 2>&1; then
  if MARKETPLACE_LIST="$(codex plugin marketplace list 2>&1)"; then
    REGISTERED_ROOT="$(printf '%s\n' "$MARKETPLACE_LIST" | awk -v name="$MARKETPLACE_NAME" '$1 == name {print $2; exit}')"
    if [[ -n "$REGISTERED_ROOT" && "$(realpath "$REGISTERED_ROOT" 2>/dev/null)" == "$ROOT" ]]; then
      pass "Codex marketplace is registered at the ChatGPT root"
    elif [[ -z "$REGISTERED_ROOT" ]]; then
      missing "Codex marketplace is not registered: $MARKETPLACE_NAME"
    else
      mismatch "Codex marketplace points to $REGISTERED_ROOT instead of $ROOT"
    fi
  else
    mismatch "Codex could not list marketplaces: $(printf '%s' "$MARKETPLACE_LIST" | head -n 1)"
  fi

  PLUGIN_LIST=""
  if PLUGIN_LIST="$(codex plugin list 2>&1)"; then
    PLUGIN_LINE="$(printf '%s\n' "$PLUGIN_LIST" | awk -v selector="$PLUGIN_NAME@$MARKETPLACE_NAME" '$1 == selector {print; exit}')"
    if [[ "$PLUGIN_LINE" == *"installed, enabled"* && "$PLUGIN_LINE" == *"$PLUGIN_VERSION"* ]]; then
      pass "plugin is installed and enabled at the source version"
    else
      missing "plugin is not installed/enabled at version $PLUGIN_VERSION"
    fi
    INSTALLED_PLUGIN_ROOT="$(printf '%s\n' "$PLUGIN_LINE" | awk '{print $NF}')"
    if [[ -n "$INSTALLED_PLUGIN_ROOT" && "$(realpath "$INSTALLED_PLUGIN_ROOT" 2>/dev/null)" == "$(realpath "$PLUGIN_ROOT" 2>/dev/null)" ]]; then
      pass "installed plugin source points to the ChatGPT plugin directory"
    elif [[ -n "$INSTALLED_PLUGIN_ROOT" ]]; then
      mismatch "installed plugin source points to $INSTALLED_PLUGIN_ROOT"
    fi
  else
    mismatch "Codex could not list plugins: $(printf '%s' "$PLUGIN_LIST" | head -n 1)"
  fi
fi

if [[ -n "$MARKETPLACE_NAME" && -n "$PLUGIN_NAME" && -n "$PLUGIN_VERSION" ]]; then
  CACHE_ROOT="$CODEX_STATE_ROOT/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$PLUGIN_VERSION"
  if [[ -d "$CACHE_ROOT" ]]; then
    if diff -qr --exclude='__pycache__' "$PLUGIN_ROOT" "$CACHE_ROOT" >/dev/null; then
      pass "installed plugin cache exactly matches source"
    else
      mismatch "installed plugin cache differs from source: $CACHE_ROOT"
    fi
  else
    missing "installed plugin cache: $CACHE_ROOT"
  fi
fi

if [[ "$RUN_TESTS" == true ]]; then
  if [[ -x "$ROOT/tests/validate-workflow.sh" ]]; then
    if "$ROOT/tests/validate-workflow.sh" >/tmp/codex-workflow-validation.out 2>&1; then
      pass "complete workflow validation"
    else
      mismatch "complete workflow validation; inspect /tmp/codex-workflow-validation.out"
    fi
  else
    missing "executable workflow validator: $ROOT/tests/validate-workflow.sh"
  fi
else
  info "complete workflow validation skipped by --no-tests"
fi

printf '\n'
if ((FAILURES == 0)); then
  printf 'READY: source, agents, marketplace, plugin, cache, and validation are usable.\n'
  printf 'NEXT: start a new Codex session from %s before invoking the workflow.\n' "$ROOT"
  exit 0
fi

printf 'NOT READY: %d required check(s) are missing or mismatched.\n' "$FAILURES"
printf 'Follow docs/codex-workflow-bootstrap-and-recovery.md in the reported order.\n'
exit 2
