#!/usr/bin/env python3
"""Bind a gate invocation to the work order's node-local physical NPU IDs."""

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("work_order", type=Path)
    parser.add_argument("node_private_ip")
    parser.add_argument("npu_devices")
    args = parser.parse_args()

    try:
        data = json.loads(args.work_order.read_text(encoding="utf-8"))
        nodes = data["topology"]["nodes"]
        matches = [node for node in nodes if node.get("private_ip") == args.node_private_ip]
        if len(matches) != 1:
            raise ValueError("work order does not contain exactly one matching node")
        confirmed = matches[0]["npu_devices"]
        if not isinstance(confirmed, list) or any(isinstance(value, bool) or not isinstance(value, int) for value in confirmed):
            raise ValueError("work-order NPU allocation is invalid")
        confirmed_text = ",".join(str(value) for value in confirmed)
        if confirmed_text != args.npu_devices:
            raise ValueError("gate NPU allocation differs from immutable work order")
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"NPU binding error: {error}", file=sys.stderr)
        return 2

    print(f"npu_devices: {args.npu_devices}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
