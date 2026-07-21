#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/SKILL.md"
PLUGIN_ROOT="$ROOT/plugins/verl-subagent-union-workflow"
MANIFEST="$ROOT/versions/v1/manifest.yaml"

test -s "$SKILL"
test "$(find "$ROOT/.codex/agents" -maxdepth 1 -type f -name '*.toml' | wc -l)" -eq 5
for role in baseline_runner optimized_runner workflow_supervisor benchmark_comparator experiment_reporter; do
  test -s "$ROOT/.codex/agents/$role.toml"
  rg -Fq 'Never ask the user' "$ROOT/.codex/agents/$role.toml"
  rg -Fq 'Do not spawn or delegate to nested agents' "$ROOT/.codex/agents/$role.toml"
done

rg -Fq 'max_attempts=20' "$SKILL"
rg -Fq 'resume_policy=fresh_start' "$SKILL"
rg -Fq 'step_result_policy=final_only' "$SKILL"
rg -Fq 'physical NPU allocation' "$SKILL"
rg -Fq 'Only the main controller interacts with the user' "$SKILL"
rg -Fq 'Reward values and deltas are report-only' "$SKILL"
rg -Fq '/mnt/disk2t/l30002999/images/verl-0.7.1_vllm-0.18.0_cann-8.5.1_baseline-installed.tar' "$SKILL"
rg -Fq '/mnt/disk2t:/mnt/disk2t' "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/create_role_container.sh"
rg -Fq '/mnt/sfs_turbo:/mnt/sfs_turbo' "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/create_role_container.sh"
rg -Fq -- '--npu-devices' "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/run_training_with_gates.sh"
rg -Fq 'Do not fetch, pull, push' "$SKILL"

bash -n "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/"*.sh
python3 - "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts"/*.py <<'PY'
import pathlib
import sys

for name in sys.argv[1:]:
    source = pathlib.Path(name).read_text(encoding="utf-8")
    compile(source, name, "exec")
PY
test -s "$ROOT/docs/verl-rollout8-pre-run-confirmation.html"

bash "$ROOT/tests/test-runtime-contracts.sh"

(cd "$ROOT/versions/v1" && sha256sum -c SHA256SUMS)
PATCH_PATH="$(awk '/^  path:/ {print $2}' "$MANIFEST")"
PATCH_SHA="$(awk '/^  sha256:/ {print $2}' "$MANIFEST")"
test "$(sha256sum "$ROOT/versions/v1/$PATCH_PATH" | awk '{print $1}')" = "$PATCH_SHA"

for script_name in create_role_container run_training_with_gates; do
  expected_hash="$(awk -v key="${script_name}_sha256:" '$1 == key {print $2}' "$MANIFEST")"
  actual_hash="$(sha256sum "$PLUGIN_ROOT/skills/verl-subagent-union-workflow/scripts/${script_name}.sh" | awk '{print $1}')"
  test "$actual_hash" = "$expected_hash"
done

BASE_COMMIT="$(awk '/^  base_commit:/ {print $2}' "$MANIFEST")"
PATCH_FILE="$ROOT/versions/v1/$PATCH_PATH"
PATCH_REPLAY="$(mktemp -d)"
trap 'rm -rf "$PATCH_REPLAY"' EXIT
REPOSITORY_ROOT="$(git -C "$ROOT" rev-parse --show-toplevel)"
git -C "$REPOSITORY_ROOT" archive "$BASE_COMMIT" | tar -x -C "$PATCH_REPLAY"
git -C "$PATCH_REPLAY" apply "$PATCH_FILE"
test -s "$PATCH_REPLAY/.codex/agents/baseline_runner.toml"
test -s "$PATCH_REPLAY/plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json"
test -s "$PATCH_REPLAY/tests/validate-workflow.sh"

PLUGIN_VERSION="$(python3 - "$PLUGIN_ROOT/.codex-plugin/plugin.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as manifest_file:
    print(json.load(manifest_file)["version"])
PY
)"
CACHE_ROOT="/root/.codex/plugins/cache/oh-my-openagent-local/verl-subagent-union-workflow/$PLUGIN_VERSION"
test -d "$CACHE_ROOT"
diff -qr --exclude='__pycache__' "$PLUGIN_ROOT" "$CACHE_ROOT"

python3 -m py_compile "$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/validate_intake.py"
"$ROOT/tests/test-intake-and-gates.sh"
"$ROOT/tests/test-runtime-contracts.sh"
"$ROOT/tests/validate-architecture-isolation.sh"

echo 'workflow validation passed'
