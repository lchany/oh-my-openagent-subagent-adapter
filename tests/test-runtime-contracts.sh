#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

INTAKE="$TMP_ROOT/intake.json"
WORKSPACE="$TMP_ROOT/new-workspace"
CONFIRMED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$INTAKE" <<EOF
{
  "schema_version": 1,
  "confirmation_token": "CONFIRM_COMPLETE_INTAKE",
  "confirmed_at": "$CONFIRMED_AT",
  "run_id": "rollout8-v1",
  "workspace": "$WORKSPACE",
  "containers": {
    "baseline": {"name": "baseline-v1", "source_root": "/workspace/baseline", "image_plan": "confirmed local archive", "create_if_missing": true},
    "optimized": {"name": "optimized-v1", "source_root": "/workspace/optimized", "image_plan": "confirmed local archive", "create_if_missing": true}
  },
  "topology": {
    "mode": "single_node",
    "node_count": 1,
    "execution_mode": "sequential_same_allocation",
    "nodes": [{"name": "node-a", "private_ip": "10.0.0.59", "npu_devices": [8, 9, 10, 11, 12, 13, 14, 15]}]
  },
  "paths": {"model": "/models/model", "train_dataset": "/data/train.parquet", "eval_dataset": null},
  "workload": {"steps": 20, "batch_sizes": {"train_batch_size": 8, "ppo_mini_batch_size": 8}, "rollout_count": 8, "tensor_parallel_size": 1, "seed": 1},
  "metrics": {"performance": [{"name": "mean_step_time", "unit": "seconds", "window": "all completed steps"}], "reward_metric": "reward", "reward_policy": "report_only"},
  "optimization": {"objective": "rollout equals eight source optimization", "allowed_differences": ["approved rollout8 source patch"]},
  "launcher": {"exact_override": null, "runner_may_select": true},
  "policies": {"resume_policy": "fresh_start", "resume_source": null, "step_result_policy": "final_only", "max_attempts": 20},
  "authorized_actions": ["container preparation", "task-owned cleanup"]
}
EOF

python3 "$SCRIPTS/validate_intake.py" "$INTAKE" >/dev/null

mutate_and_reject() {
  local expression="$1"
  local output="$TMP_ROOT/mutated.json"
  python3 - "$INTAKE" "$output" "$expression" <<'PY'
import json
import sys

source, output, expression = sys.argv[1:]
with open(source, encoding="utf-8") as input_file:
    data = json.load(input_file)
exec(expression, {"data": data})
with open(output, "w", encoding="utf-8") as output_file:
    json.dump(data, output_file)
PY
  if python3 "$SCRIPTS/validate_intake.py" "$output" >/dev/null 2>&1; then
    echo "validator accepted forbidden mutation: $expression" >&2
    exit 1
  fi
}

mutate_and_reject 'del data["paths"]["model"]'
mutate_and_reject 'data["confirmed_at"] = "2000-01-01T00:00:00Z"'
mutate_and_reject 'data["policies"]["resume_policy"] = "history"'
mutate_and_reject 'data["policies"]["step_result_policy"] = "implicit_per_step"'
mutate_and_reject 'data["topology"]["nodes"][0]["npu_devices"] = [8, 8, 9, 10, 11, 12, 13, 14]'

mkdir -p "$WORKSPACE"
if python3 "$SCRIPTS/validate_intake.py" "$INTAKE" >/dev/null 2>&1; then
  echo "validator accepted an existing workspace" >&2
  exit 1
fi
rmdir "$WORKSPACE"

python3 "$SCRIPTS/validate_npu_binding.py" "$INTAKE" 10.0.0.59 8,9,10,11,12,13,14,15 >/dev/null
if python3 "$SCRIPTS/validate_npu_binding.py" "$INTAKE" 10.0.0.59 0,1,2,3,4,5,6,7 >/dev/null 2>&1; then
  echo "NPU binding accepted front-eight mutation for a back-eight work order" >&2
  exit 1
fi

GATE="$SCRIPTS/run_training_with_gates.sh"
GATE_ARGS=(
  --run-id runtime-contract --phase baseline --container-role baseline --container-name baseline-v1
  --source-root /tmp/source --topology single_node --expected-nodes 1 --expected-npus 8
  --npu-devices 8,9,10,11,12,13,14,15 --output-dir /tmp/output
  --training-script /tmp/train.sh --training-config /tmp/train.yaml --work-order /tmp/work-order.json
  --container-identity-evidence /tmp/container.yaml --topology-evidence /tmp/topology.yaml
  --actor-env-evidence /tmp/actor.yaml --source-parity-evidence /tmp/source.yaml
  --metric-policy-evidence /tmp/metric.yaml --output-policy-evidence /tmp/output.yaml
  --phase-mode-evidence /tmp/phase.yaml --dry-run
)
if ASCEND_RT_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 NPU_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 bash "$GATE" "${GATE_ARGS[@]}" >"$TMP_ROOT/gate.out" 2>&1; then
  echo "gate accepted inherited front-eight allocation" >&2
  exit 1
fi
rg -Fq 'conflicts with confirmed physical NPU allocation' "$TMP_ROOT/gate.out"

if env -u ASCEND_RT_VISIBLE_DEVICES -u NPU_VISIBLE_DEVICES bash "$GATE" "${GATE_ARGS[@]}" >"$TMP_ROOT/gate-valid.out" 2>&1; then
  echo "gate unexpectedly passed without a phase workspace" >&2
  exit 1
fi
rg -Fq 'Phase workspace is missing' "$TMP_ROOT/gate-valid.out"

# Cleanup is ownership-scoped: broad process-kill primitives are forbidden and
# terminal proof must bind both current-run environment and launch session.
! rg -n '\b(pkill|killall)\b' "$GATE"
rg -Fq 'environment_owned = all' "$SCRIPTS/verify_terminal_cleanup.py"
rg -Fq 'session_owned = process_session_id == args.session_id' "$SCRIPTS/verify_terminal_cleanup.py"
rg -Fq 'task-owned NPU occupation remains' "$SCRIPTS/verify_terminal_cleanup.py"

# Exercise terminal cleanup against a synthetic owned process and then a zombie.
FAKE_PROC="$TMP_ROOT/fake-proc/123"
mkdir -p "$FAKE_PROC"
printf 'State: S (sleeping)\nNSpid:\t123\n' > "$FAKE_PROC/status"
printf '123 (train) S 1 1 123 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n' > "$FAKE_PROC/stat"
printf 'VERL_WORKFLOW_RUN_ID=runtime-contract\0VERL_WORKFLOW_PHASE=baseline\0VERL_WORKFLOW_TOPOLOGY=single_node\0VERL_WORKFLOW_CONTAINER_NAME=baseline-v1\0VERL_WORKFLOW_NPU_DEVICES=8,9,10,11,12,13,14,15\0' > "$FAKE_PROC/environ"
printf 'train\0' > "$FAKE_PROC/cmdline"
printf 'device process 123\n' > "$TMP_ROOT/npu-state"
if python3 "$SCRIPTS/verify_terminal_cleanup.py" --run-id runtime-contract --phase baseline --topology single_node --container-name baseline-v1 --npu-devices 8,9,10,11,12,13,14,15 --session-id 123 --proc-root "$TMP_ROOT/fake-proc" --npu-state "$TMP_ROOT/npu-state" --process-output "$TMP_ROOT/processes"; then
  echo 'cleanup helper accepted an owned NPU process' >&2
  exit 1
fi
sed -i 's/State: S/State: Z (zombie)/' "$FAKE_PROC/status"
python3 "$SCRIPTS/verify_terminal_cleanup.py" --run-id runtime-contract --phase baseline --topology single_node --container-name baseline-v1 --npu-devices 8,9,10,11,12,13,14,15 --session-id 123 --proc-root "$TMP_ROOT/fake-proc" --npu-state "$TMP_ROOT/npu-state" --process-output "$TMP_ROOT/processes"

echo 'runtime contract tests passed'
