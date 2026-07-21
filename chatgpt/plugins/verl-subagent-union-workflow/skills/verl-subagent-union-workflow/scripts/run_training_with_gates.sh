#!/usr/bin/env bash
set -euo pipefail

RUN_ID=""
PHASE=""
TOPOLOGY=""
CONTAINER_ROLE=""
CONTAINER_NAME=""
SOURCE_ROOT=""
EXPECTED_NODES=""
EXPECTED_NPUS=""
NPU_DEVICES=""
OUTPUT_DIR=""
TRAINING_SCRIPT=""
TRAINING_CONFIG=""
WORK_ORDER=""
CONTAINER_IDENTITY_EVIDENCE=""
TOPOLOGY_EVIDENCE=""
ACTOR_ENV_EVIDENCE=""
SOURCE_PARITY_EVIDENCE=""
METRIC_POLICY_EVIDENCE=""
OUTPUT_POLICY_EVIDENCE=""
PHASE_MODE_EVIDENCE=""
TOPOLOGY_MANIFEST=""
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE_ROOT=""
PREFLIGHT_DIR=""
PREFLIGHT_CANDIDATE=""
WORK_ORDER_REAL=""
WORK_ORDER_SHA256=""
TRAINING_SCRIPT_REAL=""
TRAINING_SCRIPT_SHA256=""
TRAINING_CONFIG_REAL=""
TRAINING_CONFIG_SHA256=""
CANONICAL_WORKLOAD=""
EVIDENCE_SET_SHA256=""
TRAINING_ARGS=()
VERIFIED_EVIDENCE_PATHS=()
VERIFIED_EVIDENCE_HASHES=()
CONTAINER_IDENTITY_MARKER="/etc/verl-workflow-container-identity"
CONTAINER_INIT_ENVIRON="/proc/1/environ"
CONTAINER_CGROUP_FILE="/proc/1/cgroup"
PROC_ROOT="/proc"
TRUSTED_CONTAINER_ID=""
TRUSTED_CONTAINER_IMAGE_ID=""
ACTOR_PRIVATE_IP=""
ACTOR_INTERFACE=""
ACTOR_ENV_EVIDENCE_SHA256=""
WRAPPER_REAL=""
WRAPPER_SHA256=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --container-role) CONTAINER_ROLE="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --source-root) SOURCE_ROOT="$2"; shift 2 ;;
    --topology) TOPOLOGY="$2"; shift 2 ;;
    --expected-nodes) EXPECTED_NODES="$2"; shift 2 ;;
    --expected-npus) EXPECTED_NPUS="$2"; shift 2 ;;
    --npu-devices) NPU_DEVICES="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --training-script) TRAINING_SCRIPT="$2"; shift 2 ;;
    --training-config) TRAINING_CONFIG="$2"; shift 2 ;;
    --work-order) WORK_ORDER="$2"; shift 2 ;;
    --container-identity-evidence) CONTAINER_IDENTITY_EVIDENCE="$2"; shift 2 ;;
    --topology-evidence) TOPOLOGY_EVIDENCE="$2"; shift 2 ;;
    --actor-env-evidence) ACTOR_ENV_EVIDENCE="$2"; shift 2 ;;
    --source-parity-evidence) SOURCE_PARITY_EVIDENCE="$2"; shift 2 ;;
    --metric-policy-evidence) METRIC_POLICY_EVIDENCE="$2"; shift 2 ;;
    --output-policy-evidence) OUTPUT_POLICY_EVIDENCE="$2"; shift 2 ;;
    --phase-mode-evidence) PHASE_MODE_EVIDENCE="$2"; shift 2 ;;
    --topology-manifest) TOPOLOGY_MANIFEST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --) shift; TRAINING_ARGS=("$@"); break ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -L "${BASH_SOURCE[0]}" || ! -f "${BASH_SOURCE[0]}" ]]; then
  echo "Gate wrapper identity validation failed"
  exit 2
fi
WRAPPER_REAL="$(realpath "${BASH_SOURCE[0]}")"
WRAPPER_SHA256="$(sha256sum "$WRAPPER_REAL" | cut -d ' ' -f 1)"

if [[ -z "$RUN_ID" || -z "$PHASE" || -z "$CONTAINER_ROLE" || -z "$CONTAINER_NAME" || -z "$SOURCE_ROOT" || -z "$TOPOLOGY" || -z "$EXPECTED_NODES" || -z "$EXPECTED_NPUS" || -z "$NPU_DEVICES" || -z "$OUTPUT_DIR" || -z "$TRAINING_SCRIPT" || -z "$TRAINING_CONFIG" || -z "$WORK_ORDER" || -z "$CONTAINER_IDENTITY_EVIDENCE" || -z "$TOPOLOGY_EVIDENCE" || -z "$ACTOR_ENV_EVIDENCE" || -z "$SOURCE_PARITY_EVIDENCE" || -z "$METRIC_POLICY_EVIDENCE" || -z "$OUTPUT_POLICY_EVIDENCE" || -z "$PHASE_MODE_EVIDENCE" ]]; then
  echo "Missing required argument"
  exit 1
fi

for path_value in "$WORKSPACE" "$SOURCE_ROOT" "$OUTPUT_DIR" "$TRAINING_SCRIPT" "$TRAINING_CONFIG" "$WORK_ORDER" "$CONTAINER_IDENTITY_EVIDENCE" "$TOPOLOGY_EVIDENCE" "$ACTOR_ENV_EVIDENCE" "$SOURCE_PARITY_EVIDENCE" "$METRIC_POLICY_EVIDENCE" "$OUTPUT_POLICY_EVIDENCE" "$PHASE_MODE_EVIDENCE"; do
  if [[ ! "$path_value" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    echo "Workflow paths must be absolute and use only safe path characters"
    exit 2
  fi
done
if [[ -n "$TOPOLOGY_MANIFEST" && ! "$TOPOLOGY_MANIFEST" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "Topology manifest path must be absolute and use only safe path characters"
  exit 2
fi

if [[ "$PHASE" != "$CONTAINER_ROLE" ]] || [[ "$CONTAINER_ROLE" != "baseline" && "$CONTAINER_ROLE" != "optimized" ]]; then
  echo "Container role does not match phase"
  exit 1
fi

if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ ! "$TOPOLOGY" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ ! "$CONTAINER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Run id, topology, or container name contains unsafe path characters"
  exit 2
fi
if [[ ! "$EXPECTED_NODES" =~ ^[1-9][0-9]*$ ]] || [[ ! "$EXPECTED_NPUS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Expected nodes and NPUs must be positive integers"
  exit 2
fi

if ! NPU_DEVICES="$(python3 - "$NPU_DEVICES" "$EXPECTED_NPUS" "$EXPECTED_NODES" <<'PY'
import re
import sys

raw, expected_total, expected_nodes = sys.argv[1:]
if int(expected_total) % int(expected_nodes):
    raise SystemExit("expected NPUs must divide evenly across expected nodes")
expected_count = int(expected_total) // int(expected_nodes)
if not re.fullmatch(r"(?:0|[1-9][0-9]*)(?:,(?:0|[1-9][0-9]*))*", raw):
    raise SystemExit("NPU device allocation must be a canonical comma-separated physical-ID list")
devices = [int(value) for value in raw.split(",")]
if len(devices) != expected_count:
    raise SystemExit("NPU device allocation count does not match --expected-npus")
if len(set(devices)) != len(devices) or devices != sorted(devices):
    raise SystemExit("NPU device allocation must contain unique ascending physical IDs")
print(",".join(str(value) for value in devices))
PY
)"; then
  echo "NPU device allocation validation failed" >&2
  exit 2
fi
for visible_variable in ASCEND_RT_VISIBLE_DEVICES NPU_VISIBLE_DEVICES; do
  inherited_value="${!visible_variable-}"
  if [[ -n "$inherited_value" && "$inherited_value" != "$NPU_DEVICES" ]]; then
    echo "Inherited ${visible_variable} conflicts with confirmed physical NPU allocation" >&2
    exit 2
  fi
done
export ASCEND_RT_VISIBLE_DEVICES="$NPU_DEVICES"
export NPU_VISIBLE_DEVICES="$NPU_DEVICES"

if [[ ! -d "${WORKSPACE}/${PHASE}" || -L "${WORKSPACE}/${PHASE}" ]]; then
  echo "Phase workspace is missing or is a symbolic link"
  exit 2
fi
PHASE_ROOT="$(realpath "${WORKSPACE}/${PHASE}")"
if [[ "$PHASE_ROOT" != "${WORKSPACE}/${PHASE}" ]]; then
  echo "Phase workspace escapes the canonical workflow root"
  exit 2
fi
PREFLIGHT_CANDIDATE="${PHASE_ROOT}/runs/${RUN_ID}/${TOPOLOGY}/preflight/${CONTAINER_NAME}"
PREFLIGHT_DIR="$(realpath -m "$PREFLIGHT_CANDIDATE")"
if [[ "$PREFLIGHT_DIR" != "${PHASE_ROOT}/"* ]]; then
  echo "Preflight directory escapes the assigned phase workspace"
  exit 2
fi
mkdir -p "$PREFLIGHT_CANDIDATE"
PREFLIGHT_DIR="$(realpath "$PREFLIGHT_CANDIDATE")"
if [[ "$PREFLIGHT_DIR" != "${PHASE_ROOT}/"* ]]; then
  echo "Preflight directory escapes the assigned phase workspace"
  exit 2
fi

OUTPUT_DIR_CANDIDATE="$(realpath -m "$OUTPUT_DIR")"
if [[ "$OUTPUT_DIR_CANDIDATE" != "${PHASE_ROOT}/"* ]] || [[ -L "$OUTPUT_DIR" ]]; then
  echo "Training output directory escapes the assigned phase workspace"
  exit 2
fi
mkdir -p "$OUTPUT_DIR_CANDIDATE"
OUTPUT_DIR="$(realpath "$OUTPUT_DIR_CANDIDATE")"
if [[ "$OUTPUT_DIR" != "${PHASE_ROOT}/"* ]]; then
  echo "Training output directory escapes the assigned phase workspace"
  exit 2
fi

for output_subdir in tmp ray hydra logs checkpoints; do
  output_subdir_path="${OUTPUT_DIR}/${output_subdir}"
  if [[ "$(realpath -m "$output_subdir_path")" != "$output_subdir_path" ]] || [[ -L "$output_subdir_path" ]]; then
    echo "Training output subdirectory escapes the canonical output directory"
    exit 2
  fi
  mkdir -p "$output_subdir_path"
done

validate_persistent_output_value() {
  local value="$1"
  local candidate
  if [[ -z "$value" || "$value" == *://* || "$value" == *'$'* || "$value" == *'`'* || "$value" == '~'* ]]; then
    echo "Training argument contains a dynamic or non-local persistent output path"
    exit 2
  fi
  if [[ "$value" == /* ]]; then
    candidate="$(realpath -m "$value")"
  else
    candidate="$(realpath -m "${OUTPUT_DIR}/${value}")"
  fi
  if [[ "$candidate" != "$OUTPUT_DIR" && "$candidate" != "${OUTPUT_DIR}/"* ]]; then
    echo "Training argument contains a persistent output path outside the canonical output directory"
    exit 2
  fi
}

for ((arg_index = 0; arg_index < ${#TRAINING_ARGS[@]}; arg_index++)); do
  training_arg="${TRAINING_ARGS[$arg_index]}"
  if [[ "$training_arg" == *ASCEND_RT_VISIBLE_DEVICES* || "$training_arg" == *NPU_VISIBLE_DEVICES* ]]; then
    echo "Training arguments must not override the confirmed physical NPU allocation"
    exit 2
  fi
  case "$training_arg" in
    --output-dir|--output_dir|--save-dir|--save_dir|--log-dir|--log_dir|--checkpoint-dir|--checkpoint_dir|--hydra-run-dir|--hydra_run_dir|--hydra-sweep-dir|--hydra_sweep_dir|--ray-tmp-dir|--ray_tmpdir|--wandb-dir|--wandb_dir)
      ((arg_index += 1))
      if ((arg_index >= ${#TRAINING_ARGS[@]})); then
        echo "Persistent output option is missing its value"
        exit 2
      fi
      validate_persistent_output_value "${TRAINING_ARGS[$arg_index]}"
      ;;
    *=*)
      training_key="${training_arg%%=*}"
      while [[ "$training_key" == +* ]]; do
        training_key="${training_key#+}"
      done
      case "$training_key" in
        --output-dir|--output_dir|--save-dir|--save_dir|--log-dir|--log_dir|--checkpoint-dir|--checkpoint_dir|--hydra-run-dir|--hydra_run_dir|--hydra-sweep-dir|--hydra_sweep_dir|--ray-tmp-dir|--ray_tmpdir|--wandb-dir|--wandb_dir|output_dir|save_dir|log_dir|checkpoint_dir|hydra.run.dir|hydra.sweep.dir|ray_tmpdir|wandb.dir|trainer.default_local_dir|trainer.default_hdfs_dir)
          validate_persistent_output_value "${training_arg#*=}"
          ;;
        *output*dir*|*save*dir*|*log*dir*|*checkpoint*dir*|*hydra*dir*|*ray*tmp*|*wandb*dir*)
          echo "Unknown persistent output option: ${training_arg}"
          exit 2
          ;;
      esac
      ;;
    *output*dir*|*save*dir*|*log*dir*|*checkpoint*dir*|*hydra*dir*|*ray*tmp*|*wandb*dir*)
      echo "Unknown persistent output option: ${training_arg}"
      exit 2
      ;;
  esac
done

MACHINE_SEAL="${PREFLIGHT_DIR}/wrapper-machine-seal.yaml"
if [[ "$DRY_RUN" == true ]]; then
  LAUNCH_ALLOW="${PREFLIGHT_DIR}/dry-run-allow.yaml"
else
  LAUNCH_ALLOW="${PREFLIGHT_DIR}/launch-allow.yaml"
fi
rm -f "$LAUNCH_ALLOW"
if [[ "$DRY_RUN" == true ]]; then
  rm -f "$MACHINE_SEAL"
fi

# Helper to record a preflight artifact.
record() {
  local file="$1"
  local status="$2"
  local detail="$3"
  cat > "$file" <<EOF
status: $status
detail: "$detail"
phase: $PHASE
topology: $TOPOLOGY
expected_nodes: $EXPECTED_NODES
expected_npus: $EXPECTED_NPUS
npu_devices: $NPU_DEVICES
training_script: $TRAINING_SCRIPT
training_config: $TRAINING_CONFIG
container_role: $CONTAINER_ROLE
container_name: $CONTAINER_NAME
source_root: $SOURCE_ROOT
output_dir: $OUTPUT_DIR
run_id: $RUN_ID
work_order_sha256: $WORK_ORDER_SHA256
EOF
}

if [[ -L "$WORK_ORDER" || ! -f "$WORK_ORDER" ]]; then
  record "${PREFLIGHT_DIR}/work-order-verify.yaml" "failed" "work-order is missing or is a symbolic link"
  exit 2
fi
WORK_ORDER_REAL="$(realpath "$WORK_ORDER")"
if [[ "$WORK_ORDER_REAL" != "${WORKSPACE}/controller/"* ]]; then
  record "${PREFLIGHT_DIR}/work-order-verify.yaml" "failed" "work-order escapes controller workspace"
  exit 2
fi
WORK_ORDER_SHA256="$(sha256sum "$WORK_ORDER_REAL" | cut -d ' ' -f 1)"
if ! python3 "$SCRIPT_DIR/validate_intake.py" "$WORK_ORDER_REAL" --allow-existing-workspace --allow-stale-confirmation > "${PREFLIGHT_DIR}/work-order-schema.yaml"; then
  record "${PREFLIGHT_DIR}/work-order-verify.yaml" "failed" "work-order complete-intake schema validation failed"
  exit 2
fi

if [[ ! -d "$SOURCE_ROOT" || -L "$TRAINING_SCRIPT" || ! -f "$TRAINING_SCRIPT" || ! -r "$TRAINING_SCRIPT" || -L "$TRAINING_CONFIG" || ! -f "$TRAINING_CONFIG" || ! -r "$TRAINING_CONFIG" ]]; then
  record "${PREFLIGHT_DIR}/training-script-verify.yaml" "failed" "source root, trusted training script, or training config is missing, unreadable, or symbolic"
  exit 2
fi
SOURCE_ROOT="$(realpath "$SOURCE_ROOT")"
TRAINING_SCRIPT_REAL="$(realpath "$TRAINING_SCRIPT")"
if [[ "$TRAINING_SCRIPT_REAL" != "${SOURCE_ROOT}/"* ]]; then
  record "${PREFLIGHT_DIR}/training-script-verify.yaml" "failed" "training script is outside the trusted container source root"
  exit 2
fi
TRAINING_SCRIPT="$TRAINING_SCRIPT_REAL"
TRAINING_SCRIPT_SHA256="$(sha256sum "$TRAINING_SCRIPT" | cut -d ' ' -f 1)"
TRAINING_CONFIG_REAL="$(realpath "$TRAINING_CONFIG")"
if [[ "$TRAINING_CONFIG_REAL" != "${PHASE_ROOT}/"* ]]; then
  record "${PREFLIGHT_DIR}/training-script-verify.yaml" "failed" "training config is outside the assigned phase workspace"
  exit 2
fi
TRAINING_CONFIG="$TRAINING_CONFIG_REAL"
TRAINING_CONFIG_SHA256="$(sha256sum "$TRAINING_CONFIG" | cut -d ' ' -f 1)"
CANONICAL_WORKLOAD="$WORKSPACE/baseline/runs/$RUN_ID/canonical-workload.sha256"
mkdir -p "$(dirname "$CANONICAL_WORKLOAD")"
if [[ ! -e "$CANONICAL_WORKLOAD" ]]; then
  if [[ "$PHASE" != baseline ]]; then
    record "${PREFLIGHT_DIR}/canonical-workload.yaml" "failed" "canonical Baseline workload hashes are missing"
    exit 2
  fi
  if ! (set -C; umask 0222; printf 'training_script_sha256: %s\ntraining_config_sha256: %s\n' "$TRAINING_SCRIPT_SHA256" "$TRAINING_CONFIG_SHA256" > "$CANONICAL_WORKLOAD"); then
    record "${PREFLIGHT_DIR}/canonical-workload.yaml" "failed" "canonical workload hashes could not be created"
    exit 2
  fi
fi
if [[ -L "$CANONICAL_WORKLOAD" || ! -f "$CANONICAL_WORKLOAD" ]] || ! python3 - "$CANONICAL_WORKLOAD" "$TRAINING_SCRIPT_SHA256" "$TRAINING_CONFIG_SHA256" <<'PY'
import re
import sys

path, script_hash, config_hash = sys.argv[1:]
values: dict[str, str] = {}
with open(path, encoding="utf-8") as workload_file:
    for raw_line in workload_file:
        key, separator, value = raw_line.rstrip("\n").partition(":")
        if not separator or key in values:
            raise SystemExit(2)
        values[key] = value.strip()
expected = {"training_script_sha256": script_hash, "training_config_sha256": config_hash}
if values != expected or any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in values.values()):
    raise SystemExit(2)
PY
then
  record "${PREFLIGHT_DIR}/canonical-workload.yaml" "failed" "training script or config differs from the canonical Baseline workload"
  exit 2
fi
record "${PREFLIGHT_DIR}/canonical-workload.yaml" "passed" "canonical training script and config hashes match"

require_passed_evidence() {
  local gate="$1"
  local evidence="$2"
  shift 2
  local output="${PREFLIGHT_DIR}/${gate}.yaml"
  local evidence_real
  evidence_real="$(realpath -m "$evidence")"
  if [[ -L "$evidence" || "$evidence_real" != "${PHASE_ROOT}/"* ]]; then
    record "$output" "failed" "evidence path escapes assigned phase workspace: ${evidence}"
    exit 2
  fi
  if [[ ! -f "$evidence_real" ]] || ! python3 - "$evidence_real" \
    status passed \
    run_id "$RUN_ID" \
    phase "$PHASE" \
    topology "$TOPOLOGY" \
    container_name "$CONTAINER_NAME" \
    expected_nodes "$EXPECTED_NODES" \
    expected_npus "$EXPECTED_NPUS" \
    npu_devices "$NPU_DEVICES" \
    work_order_sha256 "$WORK_ORDER_SHA256" \
    "$@" <<'PY'
import re
import sys

path = sys.argv[1]
expected_args = sys.argv[2:]
if len(expected_args) % 2 != 0:
    raise SystemExit(2)
expected = {expected_args[index]: expected_args[index + 1] for index in range(0, len(expected_args), 2)}
values: dict[str, str] = {}
with open(path, encoding="utf-8") as evidence_file:
    for line_number, raw_line in enumerate(evidence_file, 1):
        line = raw_line.rstrip("\n")
        if not line or line.lstrip().startswith("#"):
            continue
        if line[0].isspace():
            continue
        key, separator, value = line.partition(":")
        if not separator or not re.fullmatch(r"[a-z][a-z0-9_]*", key) or key in values:
            raise SystemExit(f"invalid or duplicate evidence key at line {line_number}")
        value = value.strip()
        if not value:
            raise SystemExit(f"invalid evidence scalar at line {line_number}")
        values[key] = value
for key, expected_value in expected.items():
    if values.get(key) != expected_value:
        raise SystemExit(f"evidence mismatch for {key}")
PY
  then
    record "$output" "failed" "missing, non-passed, or wrong run/container/work-order-bound evidence: ${evidence}"
    exit 2
  fi
  VERIFIED_EVIDENCE_PATHS+=("$evidence_real")
  VERIFIED_EVIDENCE_HASHES+=("$(sha256sum "$evidence_real" | cut -d ' ' -f 1)")
  record "$output" "passed" "verified evidence artifact: ${evidence_real}"
}

require_actor_environment() {
  local values_file="${PREFLIGHT_DIR}/actor-env-values.txt"
  if ! python3 - "$ACTOR_ENV_EVIDENCE" > "$values_file" <<'PY'
import ipaddress
import fcntl
import re
import socket
import struct
import sys

values: dict[str, str] = {}
with open(sys.argv[1], encoding="utf-8") as evidence_file:
    for line_number, raw_line in enumerate(evidence_file, 1):
        line = raw_line.rstrip("\n")
        if not line or line.lstrip().startswith("#") or line[0].isspace():
            continue
        key, separator, value = line.partition(":")
        if not separator or key in values:
            raise SystemExit(f"invalid Actor evidence key at line {line_number}")
        values[key] = value.strip()
required = {
    "gloo_socket_ifname",
    "hccl_socket_ifname",
    "ray_node_ip_address",
    "node_private_ip",
    "node_interface",
}
if any(not values.get(key) for key in required):
    raise SystemExit("Actor environment evidence is missing required network fields")
interface = values["node_interface"]
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]*", interface):
    raise SystemExit("Actor environment interface is invalid")
if values["gloo_socket_ifname"] != interface or values["hccl_socket_ifname"] != interface:
    raise SystemExit("Gloo or HCCL interface does not match node interface")
if values["ray_node_ip_address"] != values["node_private_ip"]:
    raise SystemExit("Ray node IP does not match node private IP")
try:
    address = ipaddress.ip_address(values["node_private_ip"])
except ValueError as error:
    raise SystemExit("Actor node private IP is invalid") from error
if address.version != 4:
    raise SystemExit("Actor node IP is not RFC1918 private IPv4")
octets = tuple(int(part) for part in str(address).split("."))
is_rfc1918 = (
    octets[0] == 10
    or (octets[0] == 172 and 16 <= octets[1] <= 31)
    or (octets[0] == 192 and octets[1] == 168)
)
if not is_rfc1918:
    raise SystemExit("Actor node IP is not RFC1918 private IPv4")
try:
    socket.if_nametoindex(interface)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as interface_socket:
        packed = struct.pack("256s", interface.encode()[:15])
        runtime_address = socket.inet_ntoa(fcntl.ioctl(interface_socket.fileno(), 0x8915, packed)[20:24])
except OSError as error:
    raise SystemExit("Actor node interface has no runtime IPv4 address") from error
if runtime_address != values["node_private_ip"]:
    raise SystemExit("Actor node private IP does not match runtime interface state")
print(values["node_private_ip"])
print(interface)
PY
  then
    record "${PREFLIGHT_DIR}/actor-env-verify.yaml" "failed" "Actor Gloo/HCCL/Ray private-IP or interface evidence validation failed"
    echo "Actor environment evidence validation failed" >&2
    exit 2
  fi
  mapfile -t ACTOR_ENV_VALUES < "$values_file"
  ACTOR_PRIVATE_IP="${ACTOR_ENV_VALUES[0]}"
  ACTOR_INTERFACE="${ACTOR_ENV_VALUES[1]}"
  ACTOR_ENV_EVIDENCE_SHA256="$(sha256sum "$ACTOR_ENV_EVIDENCE" | cut -d ' ' -f 1)"
}

require_topology_manifest() {
  local manifest_real
  if [[ -z "$TOPOLOGY_MANIFEST" ]]; then
    record "${PREFLIGHT_DIR}/topology-manifest.yaml" "failed" "multi-node topology manifest is required"
    exit 2
  fi
  manifest_real="$(realpath -m "$TOPOLOGY_MANIFEST")"
  if [[ -L "$TOPOLOGY_MANIFEST" || ! -f "$manifest_real" || "$manifest_real" != "${PHASE_ROOT}/"* ]]; then
    record "${PREFLIGHT_DIR}/topology-manifest.yaml" "failed" "multi-node topology manifest is missing, symbolic, or outside the phase workspace"
    exit 2
  fi
  if ! python3 - "$manifest_real" "$PHASE_ROOT" "$RUN_ID" "$PHASE" "$TOPOLOGY" "$EXPECTED_NODES" "$EXPECTED_NPUS" "$NPU_DEVICES" "$CONTAINER_NAME" "$WORK_ORDER_SHA256" "$TRAINING_SCRIPT_SHA256" "$TRAINING_CONFIG_SHA256" "$ACTOR_PRIVATE_IP" "$ACTOR_INTERFACE" "$ACTOR_ENV_EVIDENCE_SHA256" "$TRUSTED_CONTAINER_ID" "$TRUSTED_CONTAINER_IMAGE_ID" "$WRAPPER_SHA256" <<'PY'
import hashlib
import ipaddress
import os
import re
import sys


def read_flat_mapping(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    with open(path, encoding="utf-8") as mapping_file:
        for line_number, raw_line in enumerate(mapping_file, 1):
            line = raw_line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            if line[0].isspace():
                raise SystemExit(f"nested topology manifest content at line {line_number}")
            key, separator, value = line.partition(":")
            if not separator or not re.fullmatch(r"[a-z][a-z0-9_]*", key) or key in values:
                raise SystemExit(f"invalid or duplicate key at line {line_number}")
            value = value.strip()
            if not value:
                raise SystemExit(f"empty value at line {line_number}")
            values[key] = value
    return values


manifest_path, phase_root, run_id, phase, topology, expected_nodes, expected_npus, current_npu_devices, current_container, work_order_hash, training_script_hash, training_config_hash, current_private_ip, current_interface, current_actor_hash, current_container_id, current_image_id, wrapper_hash = sys.argv[1:]
manifest = read_flat_mapping(manifest_path)
required = {
    "status": "passed",
    "run_id": run_id,
    "phase": phase,
    "topology": topology,
    "expected_nodes": expected_nodes,
    "expected_npus": expected_npus,
    "work_order_sha256": work_order_hash,
    "container_count": expected_nodes,
}
for key, value in required.items():
    if manifest.get(key) != value:
        raise SystemExit(f"topology manifest mismatch for {key}")

allowed_manifest_keys = set(required)
for index in range(1, int(expected_nodes) + 1):
    allowed_manifest_keys.update(
        {
            f"container_{index}_name",
            f"container_{index}_dry_run_allow",
            f"container_{index}_sha256",
            f"container_{index}_private_ip",
            f"container_{index}_interface",
            f"container_{index}_npu_devices",
            f"container_{index}_id",
            f"container_{index}_image_id",
            f"container_{index}_actor_env_evidence",
            f"container_{index}_actor_env_sha256",
            f"container_{index}_machine_seal",
            f"container_{index}_machine_seal_sha256",
        }
    )
if set(manifest) != allowed_manifest_keys:
    raise SystemExit("topology manifest contains missing or unexpected keys")

private_ips: set[str] = set()
container_ids: set[str] = set()
for index in range(1, int(expected_nodes) + 1):
    name = manifest.get(f"container_{index}_name")
    artifact = manifest.get(f"container_{index}_dry_run_allow")
    artifact_hash = manifest.get(f"container_{index}_sha256")
    private_ip = manifest.get(f"container_{index}_private_ip")
    interface = manifest.get(f"container_{index}_interface")
    npu_devices = manifest.get(f"container_{index}_npu_devices")
    container_id = manifest.get(f"container_{index}_id")
    image_id = manifest.get(f"container_{index}_image_id")
    actor_evidence = manifest.get(f"container_{index}_actor_env_evidence")
    actor_hash = manifest.get(f"container_{index}_actor_env_sha256")
    machine_seal = manifest.get(f"container_{index}_machine_seal")
    machine_seal_hash = manifest.get(f"container_{index}_machine_seal_sha256")
    if None in (name, artifact, artifact_hash, private_ip, interface, npu_devices, container_id, image_id, actor_evidence, actor_hash, machine_seal, machine_seal_hash) or private_ip in private_ips or container_id in container_ids:
        raise SystemExit(f"missing or duplicate topology container entry {index}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
        raise SystemExit(f"unsafe topology container name {index}")
    if not re.fullmatch(r"[0-9a-f]{64}", container_id) or not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise SystemExit(f"invalid topology container identity {index}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]*", interface):
        raise SystemExit(f"invalid topology interface {index}")
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)(?:,(?:0|[1-9][0-9]*))*", npu_devices):
        raise SystemExit(f"invalid topology NPU allocation {index}")
    parsed_npu_devices = [int(value) for value in npu_devices.split(",")]
    if int(expected_npus) % int(expected_nodes) or len(parsed_npu_devices) != int(expected_npus) // int(expected_nodes) or len(set(parsed_npu_devices)) != len(parsed_npu_devices) or parsed_npu_devices != sorted(parsed_npu_devices):
        raise SystemExit(f"non-canonical topology NPU allocation {index}")
    try:
        address = ipaddress.ip_address(private_ip)
    except ValueError as error:
        raise SystemExit(f"invalid topology private IP {index}") from error
    if address.version != 4:
        raise SystemExit(f"non-private topology IP {index}")
    octets = tuple(int(part) for part in str(address).split("."))
    if not (
        octets[0] == 10
        or (octets[0] == 172 and 16 <= octets[1] <= 31)
        or (octets[0] == 192 and octets[1] == 168)
    ):
        raise SystemExit(f"non-private topology IP {index}")
    private_ips.add(private_ip)
    container_ids.add(container_id)
    artifact_real = os.path.realpath(artifact)
    expected_preflight_root = os.path.join(phase_root, "runs", run_id, topology, "preflight") + os.sep
    if os.path.islink(artifact) or not artifact_real.startswith(expected_preflight_root) or os.path.basename(artifact_real) != "dry-run-allow.yaml" or not os.path.isfile(artifact_real):
        raise SystemExit(f"invalid dry-run artifact {index}")
    with open(artifact_real, "rb") as artifact_file:
        if hashlib.sha256(artifact_file.read()).hexdigest() != artifact_hash:
            raise SystemExit(f"dry-run artifact hash mismatch {index}")
    dry_run = read_flat_mapping(artifact_real)
    dry_run_required = {
        "training_launch_allowed": "true",
        "training_started_after_preflight": "false",
        "run_id": run_id,
        "phase": phase,
        "topology": topology,
        "expected_nodes": expected_nodes,
        "expected_npus": expected_npus,
        "npu_devices": npu_devices,
        "container_name": name,
        "work_order_sha256": work_order_hash,
        "container_role": phase,
        "container_id": container_id,
        "container_image_id": image_id,
        "actor_private_ip": private_ip,
        "actor_interface": interface,
        "actor_env_evidence_sha256": actor_hash,
        "training_script_sha256": training_script_hash,
        "training_config_sha256": training_config_hash,
    }
    for key, value in dry_run_required.items():
        if dry_run.get(key) != value:
            raise SystemExit(f"dry-run artifact {index} mismatch for {key}")
    actor_real = os.path.realpath(actor_evidence)
    if os.path.islink(actor_evidence) or not actor_real.startswith(phase_root + os.sep) or not os.path.isfile(actor_real):
        raise SystemExit(f"invalid Actor environment evidence {index}")
    with open(actor_real, "rb") as actor_file:
        if hashlib.sha256(actor_file.read()).hexdigest() != actor_hash:
            raise SystemExit(f"Actor environment evidence hash mismatch {index}")
    actor = read_flat_mapping(actor_real)
    actor_required = {
        "status": "passed",
        "run_id": run_id,
        "phase": phase,
        "topology": topology,
        "container_name": name,
        "expected_nodes": expected_nodes,
        "expected_npus": expected_npus,
        "npu_devices": npu_devices,
        "work_order_sha256": work_order_hash,
        "container_role": phase,
        "container_id": container_id,
        "container_image_id": image_id,
        "gloo_socket_ifname": interface,
        "hccl_socket_ifname": interface,
        "ray_node_ip_address": private_ip,
        "node_private_ip": private_ip,
        "node_interface": interface,
    }
    for key, value in actor_required.items():
        if actor.get(key) != value:
            raise SystemExit(f"Actor environment evidence {index} mismatch for {key}")
    seal_real = os.path.realpath(machine_seal)
    if os.path.islink(machine_seal) or not seal_real.startswith(expected_preflight_root) or os.path.basename(seal_real) != "wrapper-machine-seal.yaml" or not os.path.isfile(seal_real):
        raise SystemExit(f"invalid wrapper machine seal {index}")
    with open(seal_real, "rb") as seal_file:
        if hashlib.sha256(seal_file.read()).hexdigest() != machine_seal_hash:
            raise SystemExit(f"wrapper machine seal hash mismatch {index}")
    seal = read_flat_mapping(seal_real)
    seal_required = {
        "format_version": "1",
        "producer": "run_training_with_gates.sh",
        "wrapper_sha256": wrapper_hash,
        "run_id": run_id,
        "phase": phase,
        "topology": topology,
        "container_name": name,
        "container_role": phase,
        "container_id": container_id,
        "container_image_id": image_id,
        "work_order_sha256": work_order_hash,
        "training_script_sha256": training_script_hash,
        "training_config_sha256": training_config_hash,
        "actor_private_ip": private_ip,
        "actor_interface": interface,
        "npu_devices": npu_devices,
        "actor_env_evidence_sha256": actor_hash,
        "evidence_set_sha256": dry_run.get("evidence_set_sha256", ""),
        "dry_run_allow_sha256": artifact_hash,
    }
    allowed_seal_keys = set(seal_required) | {"identity_marker_sha256", "seal_sha256"}
    if set(seal) != allowed_seal_keys or any(seal.get(key) != value for key, value in seal_required.items()):
        raise SystemExit(f"wrapper machine seal binding mismatch {index}")
    if not re.fullmatch(r"[0-9a-f]{64}", seal.get("identity_marker_sha256", "")):
        raise SystemExit(f"wrapper machine seal identity marker mismatch {index}")
    seal_payload = b"verl-wrapper-machine-seal-v1\0" + "\0".join(
        f"{key}={seal[key]}" for key in sorted(allowed_seal_keys - {"seal_sha256"})
    ).encode()
    if hashlib.sha256(seal_payload).hexdigest() != seal.get("seal_sha256"):
        raise SystemExit(f"wrapper machine seal digest mismatch {index}")
    if container_id == current_container_id and (name, private_ip, interface, npu_devices, actor_hash, image_id) != (current_container, current_private_ip, current_interface, current_npu_devices, current_actor_hash, current_image_id):
        raise SystemExit("head container Actor environment differs from topology manifest")

if current_container_id not in container_ids:
    raise SystemExit("head container is absent from topology manifest")
PY
  then
    record "${PREFLIGHT_DIR}/topology-manifest.yaml" "failed" "multi-node topology manifest validation failed"
    echo "Topology manifest validation failed" >&2
    exit 2
  fi
  record "${PREFLIGHT_DIR}/topology-manifest.yaml" "passed" "multi-node topology manifest verified"
}

# Gate 1: container role, immutable creation identity, and shared mounts
echo "[gate] Container identity and shared mounts"
IDENTITY_VALUES_FILE="${PREFLIGHT_DIR}/container-identity-values.txt"
if ! python3 - "$CONTAINER_IDENTITY_MARKER" "$CONTAINER_INIT_ENVIRON" "$CONTAINER_CGROUP_FILE" "$CONTAINER_ROLE" "$CONTAINER_NAME" > "$IDENTITY_VALUES_FILE" <<'PY'
import os
import re
import stat
import sys

marker_path, init_environ_path, cgroup_path, expected_role, expected_name = sys.argv[1:]
if os.path.islink(marker_path) or not os.path.isfile(marker_path):
    raise SystemExit("container identity marker is missing or symbolic")
marker_stat = os.stat(marker_path)
if marker_stat.st_uid != 0 or stat.S_IMODE(marker_stat.st_mode) & 0o222:
    raise SystemExit("container identity marker is not root-owned read-only state")
values: dict[str, str] = {}
with open(marker_path, encoding="utf-8") as marker_file:
    for line_number, raw_line in enumerate(marker_file, 1):
        key, separator, value = raw_line.rstrip("\n").partition(":")
        if not separator or key in values:
            raise SystemExit(f"invalid container identity marker line {line_number}")
        values[key] = value.strip()
required_keys = {
    "format_version",
    "container_role",
    "container_name",
    "container_id",
    "container_image_id",
}
if set(values) != required_keys or values["format_version"] != "1":
    raise SystemExit("container identity marker key set is invalid")
if values["container_role"] != expected_role or values["container_name"] != expected_name:
    raise SystemExit("container identity marker role or name mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", values["container_id"]):
    raise SystemExit("container identity marker container ID is invalid")
if not re.fullmatch(r"sha256:[0-9a-f]{64}", values["container_image_id"]):
    raise SystemExit("container identity marker image ID is invalid")
with open(init_environ_path, "rb") as environ_file:
    initial_environment = dict(
        entry.split(b"=", 1) for entry in environ_file.read().split(b"\0") if b"=" in entry
    )
trusted_environment = {
    "container_role": initial_environment.get(b"VERL_WORKFLOW_CONTAINER_ROLE", b"").decode(),
    "container_name": initial_environment.get(b"VERL_WORKFLOW_CONTAINER_NAME", b"").decode(),
    "container_image_id": initial_environment.get(b"VERL_WORKFLOW_CONTAINER_IMAGE_ID", b"").decode(),
}
if any(values[key] != value for key, value in trusted_environment.items()):
    raise SystemExit("container identity marker does not match Docker creation environment")
with open(cgroup_path, encoding="utf-8") as cgroup_file:
    runtime_ids = {
        match
        for line in cgroup_file
        for match in re.findall(r"(?:/docker/|/docker-)([0-9a-f]{64})(?:$|[/.])", line.rstrip("\n"))
    }
if len(runtime_ids) != 1:
    raise SystemExit("runtime cgroup does not expose one full Docker container ID")
if runtime_ids.pop() != values["container_id"]:
    raise SystemExit("runtime cgroup container ID does not match the trusted container ID")
print(values["container_id"])
print(values["container_image_id"])
PY
then
  record "${PREFLIGHT_DIR}/container-identity.yaml" "failed" "trusted container identity marker validation failed"
  echo "Trusted container identity marker validation failed" >&2
  exit 2
fi
mapfile -t TRUSTED_IDENTITY_VALUES < "$IDENTITY_VALUES_FILE"
TRUSTED_CONTAINER_ID="${TRUSTED_IDENTITY_VALUES[0]}"
TRUSTED_CONTAINER_IMAGE_ID="${TRUSTED_IDENTITY_VALUES[1]}"
CONTAINER_IDENTITY_MARKER_SHA256="$(sha256sum "$CONTAINER_IDENTITY_MARKER" | cut -d ' ' -f 1)"
require_passed_evidence "container-identity" "$CONTAINER_IDENTITY_EVIDENCE" \
  container_role "$CONTAINER_ROLE" \
  container_id "$TRUSTED_CONTAINER_ID" \
  container_image_id "$TRUSTED_CONTAINER_IMAGE_ID" \
  identity_marker_sha256 "$CONTAINER_IDENTITY_MARKER_SHA256"
if [[ ! -d /mnt/disk2t || ! -d /mnt/sfs_turbo ]]; then
  record "${PREFLIGHT_DIR}/mount-verify.yaml" "failed" "required /mnt/disk2t or /mnt/sfs_turbo mount is missing"
  exit 2
fi
record "${PREFLIGHT_DIR}/mount-verify.yaml" "passed" "required shared mounts visible"

# Gate 2: container-local runtime source
echo "[gate] Runtime source"
if [[ ! -d "$SOURCE_ROOT" ]]; then
  record "${PREFLIGHT_DIR}/runtime-source.yaml" "failed" "container-local source root missing"
  exit 2
fi
if ! python3 - "$SOURCE_ROOT" > "${PREFLIGHT_DIR}/runtime-source.yaml" <<'PY'
import importlib.util
import json
import os
import sys

source_root = os.path.realpath(sys.argv[1])
origins = {}
for name in ("verl", "vllm"):
    spec = importlib.util.find_spec(name)
    origins[name] = None if spec is None or spec.origin is None else os.path.realpath(spec.origin)

verl_origin = origins["verl"]
if verl_origin is None or not (verl_origin == source_root or verl_origin.startswith(source_root + os.sep)):
    raise SystemExit(2)

print("status: passed")
print("source_root: " + json.dumps(source_root))
print("verl_origin: " + json.dumps(origins["verl"]))
print("vllm_origin: " + json.dumps(origins["vllm"]))
PY
then
  record "${PREFLIGHT_DIR}/runtime-source.yaml" "failed" "verl import does not resolve under the assigned container-local source root"
  exit 2
fi
python3 -m pip show verl vllm > "${PREFLIGHT_DIR}/package-manifest.txt" 2>&1 || true
SOURCE_FINGERPRINT="$(find "$SOURCE_ROOT" -type f -not -path '*/.git/*' -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum | sha256sum | awk '{print $1}')"
record "${PREFLIGHT_DIR}/source-fingerprint.yaml" "passed" "source content fingerprint=${SOURCE_FINGERPRINT}"

# Gate 3: workflow-owned Ray/process state must already be clean. A failure
# blocks launch; the same Runner diagnoses, repairs, and retries in its session.
echo "[gate] Ray/process state"
python3 - "${PREFLIGHT_DIR}/ray-processes.txt" <<'PY'
import os
import sys

targets = ("verl.trainer.main_ppo", "ray" + "let", "gcs" + "_server", "VLLM::Worker_TP")
with open(sys.argv[1], "w", encoding="utf-8") as output_file:
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            with open(f"/proc/{entry.name}/stat", encoding="utf-8") as stat_file:
                state = stat_file.read().rsplit(") ", 1)[1].split()[0]
            with open(f"/proc/{entry.name}/cmdline", "rb") as cmdline_file:
                command = cmdline_file.read().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if state != "Z" and any(target in command for target in targets):
            output_file.write(f"{entry.name} {state} {command}\n")
PY
if [[ -s "${PREFLIGHT_DIR}/ray-processes.txt" ]]; then
  record "${PREFLIGHT_DIR}/ray-cleanup.yaml" "failed" "stale or active workflow processes detected; repair required"
  exit 2
fi
record "${PREFLIGHT_DIR}/ray-cleanup.yaml" "passed" "no stale workflow processes detected"

# Gate 4: Topology verification
echo "[gate] Topology verification"
require_passed_evidence "topology-verify" "$TOPOLOGY_EVIDENCE"

# Gate 5: Actor network env
echo "[gate] Actor network env"
require_passed_evidence "actor-env-verify" "$ACTOR_ENV_EVIDENCE" \
  container_role "$CONTAINER_ROLE" \
  container_id "$TRUSTED_CONTAINER_ID" \
  container_image_id "$TRUSTED_CONTAINER_IMAGE_ID"
require_actor_environment
if ! python3 "$SCRIPT_DIR/validate_npu_binding.py" "$WORK_ORDER_REAL" "$ACTOR_PRIVATE_IP" "$NPU_DEVICES" > "${PREFLIGHT_DIR}/npu-work-order-binding.yaml"; then
  record "${PREFLIGHT_DIR}/npu-work-order-binding.yaml" "failed" "physical NPU allocation differs from immutable work order"
  exit 2
fi

# Gate 6: Source parity
echo "[gate] Source parity"
require_passed_evidence "source-parity" "$SOURCE_PARITY_EVIDENCE"

# Gate 7: Metric policy
echo "[gate] Metric policy"
require_passed_evidence "metric-policy" "$METRIC_POLICY_EVIDENCE"

echo "[gate] Persistent output policy"
require_passed_evidence "output-policy" "$OUTPUT_POLICY_EVIDENCE" \
  output_dir "$OUTPUT_DIR" \
  checkpoint_dir "$OUTPUT_DIR/checkpoints" \
  hydra_run_dir "$OUTPUT_DIR/hydra" \
  hydra_sweep_dir "$OUTPUT_DIR/hydra" \
  log_dir "$OUTPUT_DIR/logs" \
  ray_tmpdir "$OUTPUT_DIR/ray" \
  wandb_dir "$OUTPUT_DIR/logs" \
  tmpdir "$OUTPUT_DIR/tmp" \
  training_script_sha256 "$TRAINING_SCRIPT_SHA256" \
  training_config_sha256 "$TRAINING_CONFIG_SHA256" \
  persistent_paths_verified true
record "${PREFLIGHT_DIR}/output-policy.yaml" "passed" "persistent output policy verified"

# Gate 8: Launch-time preflight
echo "[gate] Launch-time preflight"
if [[ ! -f "$TRAINING_SCRIPT" || ! -r "$TRAINING_SCRIPT" ]]; then
  record "${PREFLIGHT_DIR}/launch-preflight.yaml" "failed" "training script is missing or unreadable"
  exit 2
fi
if ! command -v setsid >/dev/null 2>&1 || ! command -v npu-smi >/dev/null 2>&1 || ! npu-smi info > "${PREFLIGHT_DIR}/npu-smi.txt" 2>&1; then
  record "${PREFLIGHT_DIR}/launch-preflight.yaml" "failed" "setsid or npu-smi is unavailable, or NPU inspection failed"
  exit 2
fi
if [[ "${ASCEND_RT_VISIBLE_DEVICES-}" != "$NPU_DEVICES" || "${NPU_VISIBLE_DEVICES-}" != "$NPU_DEVICES" ]]; then
  record "${PREFLIGHT_DIR}/npu-allocation.yaml" "failed" "runtime visible-device environment differs from confirmed physical NPU allocation"
  exit 2
fi
record "${PREFLIGHT_DIR}/npu-allocation.yaml" "passed" "confirmed physical NPU allocation is active: ${NPU_DEVICES}"
record "${PREFLIGHT_DIR}/launch-preflight.yaml" "passed" "training script readable and npu-smi inspection succeeded"

# Gate 9: Phase mode verification
if [[ "$PHASE" == "baseline" ]]; then
  require_passed_evidence "baseline-mode-verify" "$PHASE_MODE_EVIDENCE"
else
  require_passed_evidence "optimized-mode-verify" "$PHASE_MODE_EVIDENCE"
fi

EVIDENCE_SET_SHA256="$({
  for ((evidence_index = 0; evidence_index < ${#VERIFIED_EVIDENCE_PATHS[@]}; evidence_index++)); do
    printf '%s  %s\n' "${VERIFIED_EVIDENCE_HASHES[$evidence_index]}" "${VERIFIED_EVIDENCE_PATHS[$evidence_index]}"
  done
} | sha256sum | cut -d ' ' -f 1)"

if [[ "$DRY_RUN" == false ]] && ((EXPECTED_NODES > 1)); then
  require_topology_manifest
fi

# Write launch-allow.yaml atomically.
LAUNCH_ALLOW_TMP="$(mktemp "${PREFLIGHT_DIR}/.launch-allow.XXXXXX")"
cat > "$LAUNCH_ALLOW_TMP" <<EOF
training_launch_allowed: true
ray_cleanup_passed: true
container_role_verified: true
container_identity_verified: true
shared_mounts_verified: true
runtime_source_verified: true
source_fingerprint_recorded: true
topology_verified: true
actor_network_env_verified: true
actor_private_ip: $ACTOR_PRIVATE_IP
actor_interface: $ACTOR_INTERFACE
actor_env_evidence_sha256: $ACTOR_ENV_EVIDENCE_SHA256
source_parity_verified: true
metric_policy_verified: true
persistent_output_policy_verified: true
launch_preflight_verified: true
phase_mode_verified: true
training_started_after_preflight: $([[ "$DRY_RUN" == true ]] && echo false || echo true)
training_launch_method: gate_wrapper
training_script_directly_invoked: false
run_id: $RUN_ID
phase: $PHASE
topology: $TOPOLOGY
expected_nodes: $EXPECTED_NODES
expected_npus: $EXPECTED_NPUS
npu_devices: $NPU_DEVICES
container_role: $CONTAINER_ROLE
container_name: $CONTAINER_NAME
container_id: $TRUSTED_CONTAINER_ID
container_image_id: $TRUSTED_CONTAINER_IMAGE_ID
source_root: $SOURCE_ROOT
source_fingerprint: $SOURCE_FINGERPRINT
output_dir: $OUTPUT_DIR
work_order: $WORK_ORDER_REAL
work_order_sha256: $WORK_ORDER_SHA256
training_script_sha256: $TRAINING_SCRIPT_SHA256
training_config_sha256: $TRAINING_CONFIG_SHA256
evidence_set_sha256: $EVIDENCE_SET_SHA256
EOF
chmod 0444 "$LAUNCH_ALLOW_TMP"
mv -f "$LAUNCH_ALLOW_TMP" "$LAUNCH_ALLOW"

if [[ "$DRY_RUN" == true ]]; then
  if [[ "$(sha256sum "$WRAPPER_REAL" | cut -d ' ' -f 1)" != "$WRAPPER_SHA256" ]] \
    || [[ "$(sha256sum "$CONTAINER_IDENTITY_MARKER" | cut -d ' ' -f 1)" != "$CONTAINER_IDENTITY_MARKER_SHA256" ]] \
    || [[ "$(sha256sum "$ACTOR_ENV_EVIDENCE" | cut -d ' ' -f 1)" != "$ACTOR_ENV_EVIDENCE_SHA256" ]] \
    || [[ "$(sha256sum "$WORK_ORDER_REAL" | cut -d ' ' -f 1)" != "$WORK_ORDER_SHA256" ]] \
    || [[ "$(sha256sum "$TRAINING_SCRIPT" | cut -d ' ' -f 1)" != "$TRAINING_SCRIPT_SHA256" ]] \
    || [[ "$(sha256sum "$TRAINING_CONFIG" | cut -d ' ' -f 1)" != "$TRAINING_CONFIG_SHA256" ]]; then
    rm -f "$LAUNCH_ALLOW"
    echo "Wrapper machine seal source changed during dry-run" >&2
    exit 2
  fi
  DRY_RUN_ALLOW_SHA256="$(sha256sum "$LAUNCH_ALLOW" | cut -d ' ' -f 1)"
  MACHINE_SEAL_TMP="$(mktemp "${PREFLIGHT_DIR}/.wrapper-machine-seal.XXXXXX")"
  python3 - "$MACHINE_SEAL_TMP" \
    "$WRAPPER_SHA256" "$RUN_ID" "$PHASE" "$TOPOLOGY" "$CONTAINER_NAME" "$CONTAINER_ROLE" \
    "$TRUSTED_CONTAINER_ID" "$TRUSTED_CONTAINER_IMAGE_ID" "$CONTAINER_IDENTITY_MARKER_SHA256" \
    "$WORK_ORDER_SHA256" "$TRAINING_SCRIPT_SHA256" "$TRAINING_CONFIG_SHA256" "$NPU_DEVICES" \
    "$ACTOR_PRIVATE_IP" "$ACTOR_INTERFACE" "$ACTOR_ENV_EVIDENCE_SHA256" "$EVIDENCE_SET_SHA256" "$DRY_RUN_ALLOW_SHA256" <<'PY'
import hashlib
import sys

keys = (
    "wrapper_sha256", "run_id", "phase", "topology", "container_name", "container_role",
    "container_id", "container_image_id", "identity_marker_sha256", "work_order_sha256",
    "training_script_sha256", "training_config_sha256", "npu_devices", "actor_private_ip", "actor_interface",
    "actor_env_evidence_sha256", "evidence_set_sha256", "dry_run_allow_sha256",
)
path = sys.argv[1]
if len(sys.argv[2:]) != len(keys):
    raise SystemExit("invalid wrapper machine seal input")
values = dict(zip(keys, sys.argv[2:]))
values = {"format_version": "1", "producer": "run_training_with_gates.sh", **values}
payload = b"verl-wrapper-machine-seal-v1\0" + "\0".join(
    f"{key}={values[key]}" for key in sorted(values)
).encode()
values["seal_sha256"] = hashlib.sha256(payload).hexdigest()
with open(path, "w", encoding="utf-8") as seal_file:
    for key, value in values.items():
        seal_file.write(f"{key}: {value}\n")
PY
  chmod 0444 "$MACHINE_SEAL_TMP"
  mv -f "$MACHINE_SEAL_TMP" "$MACHINE_SEAL"
fi

# Launch real training through the confirmed training script.
# The runner must not invoke the training script directly; this wrapper is the only valid launch path.
if [[ "$DRY_RUN" == true ]]; then
  echo "[gate] dry-run completed; training was not launched"
  exit 0
fi
cd "$OUTPUT_DIR"
export VERL_WORKFLOW_OUTPUT_DIR="$OUTPUT_DIR"
export VERL_WORKFLOW_RUN_ID="$RUN_ID"
export VERL_WORKFLOW_PHASE="$PHASE"
export VERL_WORKFLOW_TOPOLOGY="$TOPOLOGY"
export VERL_WORKFLOW_CONTAINER_NAME="$CONTAINER_NAME"
export VERL_WORKFLOW_EXPECTED_NODES="$EXPECTED_NODES"
export VERL_WORKFLOW_EXPECTED_NPUS="$EXPECTED_NPUS"
export VERL_WORKFLOW_NPU_DEVICES="$NPU_DEVICES"
export VERL_WORKFLOW_CONTAINER_ROLE="$CONTAINER_ROLE"
export TMPDIR="$OUTPUT_DIR/tmp"
export RAY_TMPDIR="$OUTPUT_DIR/ray"
export HYDRA_RUN_DIR="$OUTPUT_DIR/hydra"
export HYDRA_SWEEP_DIR="$OUTPUT_DIR/hydra"
export WANDB_DIR="$OUTPUT_DIR/logs"
export VERL_LOG_DIR="$OUTPUT_DIR/logs"
export VERL_CHECKPOINT_DIR="$OUTPUT_DIR/checkpoints"
export GLOO_SOCKET_IFNAME="$ACTOR_INTERFACE"
export HCCL_SOCKET_IFNAME="$ACTOR_INTERFACE"
export RAY_NODE_IP_ADDRESS="$ACTOR_PRIVATE_IP"
set +e
setsid bash "$TRAINING_SCRIPT" "${TRAINING_ARGS[@]}" &
TRAINING_LEADER_PID=$!
wait "$TRAINING_LEADER_PID"
TRAINING_EXIT_CODE=$?
TASK_SESSION_ID="$TRAINING_LEADER_PID"
set -e
find "$OUTPUT_DIR" -type f -print | LC_ALL=C sort > "${PREFLIGHT_DIR}/persistent-output-manifest.txt"
record "${PREFLIGHT_DIR}/persistent-output-verify.yaml" "passed" "workflow-owned persistent output manifest recorded under assigned phase workspace"

TERMINAL_NPU_STATE="${PREFLIGHT_DIR}/terminal-npu-smi.txt"
TERMINAL_PROCESS_STATE="${PREFLIGHT_DIR}/terminal-workflow-processes.txt"
TERMINAL_CLEANUP_FAILURE=""
if ! npu-smi info > "$TERMINAL_NPU_STATE" 2>&1; then
  TERMINAL_CLEANUP_FAILURE="terminal cleanup proof unavailable because npu-smi inspection failed"
elif ! TERMINAL_CLEANUP_FAILURE="$(python3 "$SCRIPT_DIR/verify_terminal_cleanup.py" \
  --run-id "$RUN_ID" --phase "$PHASE" --topology "$TOPOLOGY" \
  --container-name "$CONTAINER_NAME" --npu-devices "$NPU_DEVICES" \
  --session-id "$TASK_SESSION_ID" --proc-root "$PROC_ROOT" \
  --npu-state "$TERMINAL_NPU_STATE" --process-output "$TERMINAL_PROCESS_STATE" 2>&1)"; then
  if [[ -z "$TERMINAL_CLEANUP_FAILURE" ]]; then
    TERMINAL_CLEANUP_FAILURE="terminal cleanup proof unavailable because task-owned process inspection failed"
  fi
fi

if [[ -n "$TERMINAL_CLEANUP_FAILURE" ]]; then
  record "${PREFLIGHT_DIR}/terminal-cleanup.yaml" "failed" "${TERMINAL_CLEANUP_FAILURE}; training_exit_code=${TRAINING_EXIT_CODE}"
  echo "Terminal cleanup proof failed: $TERMINAL_CLEANUP_FAILURE" >&2
  exit 125
fi
record "${PREFLIGHT_DIR}/terminal-cleanup.yaml" "passed" "no task-owned Ray/workflow process or NPU occupation remains; training_exit_code=${TRAINING_EXIT_CODE}"
exit "$TRAINING_EXIT_CODE"
