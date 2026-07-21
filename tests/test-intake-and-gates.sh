#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/validate_intake.py"
GATE="$ROOT/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/scripts/run_training_with_gates.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP/intake.json" "$TMP/workspace" <<'PY'
import json, sys
from datetime import datetime, timezone
out, workspace = sys.argv[1:]
data = {
  "schema_version": 1, "confirmation_token": "CONFIRM_COMPLETE_INTAKE", "confirmed_at": datetime.now(timezone.utc).isoformat(), "run_id": "test-run", "workspace": workspace,
  "containers": {"baseline": {"name": "baseline-test", "source_root": "/opt/baseline", "image_plan": "local-image", "create_if_missing": False}, "optimized": {"name": "optimized-test", "source_root": "/opt/optimized", "image_plan": "local-image", "create_if_missing": False}},
  "topology": {"mode": "single_node", "node_count": 1, "execution_mode": "sequential_same_allocation", "nodes": [{"name": "node", "private_ip": "192.168.10.59", "npu_devices": list(range(8, 16))}]},
  "paths": {"model": "/data/model", "train_dataset": "/data/train", "eval_dataset": None},
  "workload": {"steps": 1, "batch_sizes": {"train": 1, "rollout": 1}, "rollout_count": 8, "tensor_parallel_size": 8, "seed": 1},
  "metrics": {"performance": [{"name": "step_time", "unit": "ms", "window": "terminal_mean"}], "reward_metric": "reward", "reward_policy": "report_only"},
  "optimization": {"objective": "rollout8 source optimization", "allowed_differences": ["approved source patch"]}, "launcher": {"exact_override": None, "runner_may_select": True},
  "policies": {"resume_policy": "fresh_start", "resume_source": None, "step_result_policy": "final_only", "max_attempts": 20}, "authorized_actions": ["create role container", "start Ray", "run training", "cleanup owned state"],
}
json.dump(data, open(out, "w"), indent=2)
PY
python3 "$VALIDATOR" "$TMP/intake.json" >/dev/null

python3 - "$TMP/intake.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); del d["workload"]["steps"]; json.dump(d, open(p, "w"))
PY
if python3 "$VALIDATOR" "$TMP/intake.json" 2>/dev/null; then exit 1; fi
python3 - "$TMP/intake.json" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
p = sys.argv[1]; d = json.load(open(p)); d["workload"]["steps"] = 1; d["confirmed_at"] = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat(); json.dump(d, open(p, "w"))
PY
if python3 "$VALIDATOR" "$TMP/intake.json" 2>/dev/null; then exit 1; fi

base_args=(--run-id t --phase baseline --container-role baseline --container-name c --source-root /tmp/source --topology single --expected-nodes 1 --expected-npus 8 --output-dir /tmp/out --training-script /tmp/source/train.sh --training-config /tmp/config --work-order /tmp/work-order --container-identity-evidence /tmp/e1 --topology-evidence /tmp/e2 --actor-env-evidence /tmp/e3 --source-parity-evidence /tmp/e4 --metric-policy-evidence /tmp/e5 --output-policy-evidence /tmp/e6 --phase-mode-evidence /tmp/e7 --dry-run)
if ASCEND_RT_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 "$GATE" "${base_args[@]}" --npu-devices 8,9,10,11,12,13,14,15 -- >/dev/null 2>&1; then exit 1; fi
if "$GATE" "${base_args[@]}" --npu-devices 8,9,10,11,12,13,14 -- >/dev/null 2>&1; then exit 1; fi
if "$GATE" "${base_args[@]}" --npu-devices 8,9,10,11,12,13,14,15 -- >/dev/null 2>&1; then exit 1; fi

echo 'intake and NPU gate tests passed'
