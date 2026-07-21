#!/usr/bin/env python3
"""Prove that no process or NPU PID owned by one workflow launch remains."""

import argparse
import os
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--topology", required=True)
    parser.add_argument("--container-name", required=True)
    parser.add_argument("--npu-devices", required=True)
    parser.add_argument("--session-id", required=True, type=int)
    parser.add_argument("--proc-root", type=Path, default=Path("/proc"))
    parser.add_argument("--npu-state", type=Path, required=True)
    parser.add_argument("--process-output", type=Path, required=True)
    args = parser.parse_args()

    expected = {
        b"VERL_WORKFLOW_RUN_ID": args.run_id.encode(),
        b"VERL_WORKFLOW_PHASE": args.phase.encode(),
        b"VERL_WORKFLOW_TOPOLOGY": args.topology.encode(),
        b"VERL_WORKFLOW_CONTAINER_NAME": args.container_name.encode(),
        b"VERL_WORKFLOW_NPU_DEVICES": args.npu_devices.encode(),
    }
    found: list[tuple[int, int, str]] = []
    try:
        entries = list(os.scandir(args.proc_root))
    except OSError as error:
        print(f"terminal cleanup proof cannot read proc root: {error}", file=sys.stderr)
        return 2

    for entry in entries:
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if args.proc_root == Path("/proc") and pid in (os.getpid(), os.getppid()):
            continue
        try:
            process_root = args.proc_root / entry.name
            status_lines = (process_root / "status").read_text(encoding="utf-8").splitlines()
            if any(line.startswith("State:") and "Z (zombie)" in line for line in status_lines):
                continue
            nspid_lines = [line for line in status_lines if line.startswith("NSpid:")]
            if len(nspid_lines) != 1:
                raise PermissionError(f"unprovable NSpid state for PID {pid}")
            namespace_pids = [int(value) for value in nspid_lines[0].split()[1:]]
            if not namespace_pids or namespace_pids[-1] != pid:
                raise PermissionError(f"invalid NSpid state for PID {pid}")
            host_pid = namespace_pids[0]
            stat_fields = (process_root / "stat").read_text(encoding="utf-8").rsplit(") ", 1)[1].split()
            process_session_id = int(stat_fields[3])
            environment = dict(
                item.split(b"=", 1)
                for item in (process_root / "environ").read_bytes().split(b"\0")
                if b"=" in item
            )
            environment_owned = all(environment.get(key) == value for key, value in expected.items())
            session_owned = process_session_id == args.session_id
            if not environment_owned and not session_owned:
                continue
            command = (process_root / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
        except FileNotFoundError:
            continue
        except (PermissionError, OSError, ValueError, IndexError) as error:
            print(f"unreadable task process state for PID {pid}: {error}", file=sys.stderr)
            return 2
        found.append((pid, host_pid, command))

    args.process_output.write_text(
        "".join(f"{pid}\t{host_pid}\t{command}\n" for pid, host_pid, command in sorted(found)),
        encoding="utf-8",
    )
    try:
        npu_state = args.npu_state.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"terminal cleanup proof cannot read NPU state: {error}", file=sys.stderr)
        return 2
    owned_host_pids = {str(host_pid) for _, host_pid, _ in found}
    if any(re.search(rf"(?<![0-9]){re.escape(pid)}(?![0-9])", npu_state) for pid in owned_host_pids):
        print("task-owned NPU occupation remains after terminal training", file=sys.stderr)
        return 3
    if found:
        print("task-owned Ray or workflow processes remain after terminal training", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
