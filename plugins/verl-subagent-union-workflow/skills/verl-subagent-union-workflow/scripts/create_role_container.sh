#!/usr/bin/env bash
# Create one role container for verl-subagent-union-workflow.
# This script is intentionally fail-closed: it never replaces an existing
# container. The matching Runner may call it during same-session self-healing
# when its assigned role container is missing.

set -euo pipefail

ROLE=""
NAME=""
IMAGE=""
IDENTITY_MARKER="/etc/verl-workflow-container-identity"

usage() {
  cat <<'EOF'
Usage: create_role_container.sh --role baseline|optimized --name NAME --image IMAGE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ "$ROLE" != "baseline" && "$ROLE" != "optimized" ]] || [[ -z "$NAME" || -z "$IMAGE" ]]; then
  usage >&2
  exit 2
fi

if docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "refusing to replace existing container: $NAME" >&2
  exit 3
fi

IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE")"
CGROUPNS_ARGS=()
if docker run --help 2>&1 | grep -q -- '--cgroupns'; then
  CGROUPNS_ARGS=(--cgroupns host)
fi
docker run -d \
  --name "$NAME" \
  --runtime ascend \
  --privileged \
  --network host \
  --ipc host \
  "${CGROUPNS_ARGS[@]}" \
  --security-opt label=disable \
  --env "VERL_WORKFLOW_CONTAINER_ROLE=$ROLE" \
  --env "VERL_WORKFLOW_CONTAINER_NAME=$NAME" \
  --env "VERL_WORKFLOW_CONTAINER_IMAGE_ID=$IMAGE_ID" \
  --volume /usr/local/bin/npu-smi:/usr/local/bin/npu-smi:ro \
  --volume /usr/local/dcmi:/usr/local/dcmi:ro \
  --volume /usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/common:ro \
  --volume /usr/local/Ascend/driver/lib64/driver:/usr/local/Ascend/driver/lib64/driver:ro \
  --volume /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info:ro \
  --volume /etc/ascend_install.info:/etc/ascend_install.info:ro \
  --volume /mnt/disk2t:/mnt/disk2t \
  --volume /mnt/sfs_turbo:/mnt/sfs_turbo \
  "$IMAGE" \
  bash -lc 'exec tail -f /dev/null' >/dev/null

docker exec "$NAME" test -d /mnt/disk2t
docker exec "$NAME" test -d /mnt/sfs_turbo
docker exec "$NAME" bash -lc 'command -v npu-smi >/dev/null && npu-smi info >/dev/null'

CONTAINER_ID="$(docker inspect --format '{{.Id}}' "$NAME")"
CONTAINER_NAME="$(docker inspect --format '{{.Name}}' "$NAME")"
CONTAINER_NAME="${CONTAINER_NAME#/}"
ACTUAL_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$NAME")"
if [[ "$ACTUAL_IMAGE_ID" != "$IMAGE_ID" ]]; then
  echo "created container image identity does not match the requested image" >&2
  exit 4
fi
docker exec "$NAME" sh -c '
  set -eu
  marker=$1
  role=$2
  name=$3
  container_id=$4
  image_id=$5
  if [ -e "$marker" ]; then
    echo "refusing to replace container identity marker: $marker" >&2
    exit 4
  fi
  umask 0222
  set -C
  printf "format_version: 1\ncontainer_role: %s\ncontainer_name: %s\ncontainer_id: %s\ncontainer_image_id: %s\n" \
    "$role" "$name" "$container_id" "$image_id" > "$marker"
  chmod 0444 "$marker"
' sh "$IDENTITY_MARKER" "$ROLE" "$CONTAINER_NAME" "$CONTAINER_ID" "$ACTUAL_IMAGE_ID"

docker exec "$NAME" cat "$IDENTITY_MARKER"
