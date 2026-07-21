#!/usr/bin/env python3
"""Validate the complete, current-run VERL work-order intake before mutation."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


PLACEHOLDER = re.compile(r"^(?:tbd|todo|unknown|unset|none|n/?a|待定|未知)$", re.IGNORECASE)
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def exact_keys(value: Any, expected: set[str], label: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return False
    missing = expected - set(value)
    extra = set(value) - expected
    if missing:
        errors.append(f"{label} missing keys: {', '.join(sorted(missing))}")
    if extra:
        errors.append(f"{label} unexpected keys: {', '.join(sorted(extra))}")
    return not missing and not extra


def non_placeholder(value: Any, label: str, errors: list[str]) -> bool:
    if not isinstance(value, str) or not value.strip() or PLACEHOLDER.fullmatch(value.strip()):
        errors.append(f"{label} is empty or a placeholder")
        return False
    return True


def absolute_path(value: Any, label: str, errors: list[str]) -> bool:
    if not non_placeholder(value, label, errors):
        return False
    if not os.path.isabs(value) or os.path.normpath(value) != value:
        errors.append(f"{label} must be a normalized absolute path")
        return False
    return True


def positive_int(value: Any, label: str, errors: list[str], maximum: int | None = None) -> bool:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        errors.append(f"{label} must be a positive integer")
        return False
    if maximum is not None and value > maximum:
        errors.append(f"{label} exceeds maximum {maximum}")
        return False
    return True


def validate(path: Path, allow_existing_workspace: bool, allow_stale_confirmation: bool) -> list[str]:
    errors: list[str] = []
    try:
        raw = path.read_bytes()
        data = json.loads(raw)
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read intake JSON: {error}"]

    top_keys = {
        "schema_version", "confirmation_token", "confirmed_at", "run_id", "workspace",
        "containers", "topology", "paths", "workload", "metrics", "optimization",
        "launcher", "policies", "authorized_actions",
    }
    if not exact_keys(data, top_keys, "intake", errors):
        return errors
    if data["schema_version"] != 1:
        errors.append("schema_version must equal 1")
    if data["confirmation_token"] != "CONFIRM_COMPLETE_INTAKE":
        errors.append("confirmation_token must equal CONFIRM_COMPLETE_INTAKE")
    if not isinstance(data["run_id"], str) or not SAFE_ID.fullmatch(data["run_id"]):
        errors.append("run_id is invalid")
    if absolute_path(data["workspace"], "workspace", errors) and not allow_existing_workspace:
        if Path(data["workspace"]).exists():
            errors.append("workspace already exists; fresh intake requires a new path")

    try:
        confirmed_at = dt.datetime.fromisoformat(str(data["confirmed_at"]).replace("Z", "+00:00"))
        if confirmed_at.tzinfo is None:
            raise ValueError("timezone missing")
        age = dt.datetime.now(dt.timezone.utc) - confirmed_at.astimezone(dt.timezone.utc)
        if not allow_stale_confirmation and (age < dt.timedelta(minutes=-5) or age > dt.timedelta(hours=24)):
            errors.append("confirmed_at is stale or in the future")
    except ValueError:
        errors.append("confirmed_at must be an ISO-8601 timestamp with timezone")

    containers = data["containers"]
    if exact_keys(containers, {"baseline", "optimized"}, "containers", errors):
        names: list[str] = []
        for role in ("baseline", "optimized"):
            item = containers[role]
            if exact_keys(item, {"name", "source_root", "image_plan", "create_if_missing"}, f"containers.{role}", errors):
                if not isinstance(item["name"], str) or not SAFE_ID.fullmatch(item["name"]):
                    errors.append(f"containers.{role}.name is invalid")
                else:
                    names.append(item["name"])
                absolute_path(item["source_root"], f"containers.{role}.source_root", errors)
                non_placeholder(item["image_plan"], f"containers.{role}.image_plan", errors)
                if not isinstance(item["create_if_missing"], bool):
                    errors.append(f"containers.{role}.create_if_missing must be boolean")
        if len(names) == 2 and names[0] == names[1]:
            errors.append("Baseline and Optimized container names must differ")

    topology = data["topology"]
    if exact_keys(topology, {"mode", "node_count", "nodes", "execution_mode"}, "topology", errors):
        if topology["mode"] not in {"single_node", "multi_node"}:
            errors.append("topology.mode must be single_node or multi_node")
        positive_int(topology["node_count"], "topology.node_count", errors)
        if topology["execution_mode"] not in {"sequential_same_allocation", "parallel_disjoint"}:
            errors.append("topology.execution_mode is invalid")
        nodes = topology["nodes"]
        if not isinstance(nodes, list) or len(nodes) != topology["node_count"]:
            errors.append("topology.nodes length must match node_count")
        else:
            node_names: set[str] = set()
            for index, node in enumerate(nodes):
                label = f"topology.nodes[{index}]"
                if not exact_keys(node, {"name", "private_ip", "npu_devices"}, label, errors):
                    continue
                if not isinstance(node["name"], str) or not SAFE_ID.fullmatch(node["name"]) or node["name"] in node_names:
                    errors.append(f"{label}.name is invalid or duplicate")
                else:
                    node_names.add(node["name"])
                try:
                    address = ipaddress.ip_address(node["private_ip"])
                    octets = tuple(int(part) for part in str(address).split("."))
                    is_rfc1918 = (
                        octets[0] == 10
                        or (octets[0] == 172 and 16 <= octets[1] <= 31)
                        or (octets[0] == 192 and octets[1] == 168)
                    )
                    if address.version != 4 or not is_rfc1918 or address.is_loopback or address.is_link_local:
                        raise ValueError
                except (ValueError, TypeError):
                    errors.append(f"{label}.private_ip must be private IPv4")
                devices = node["npu_devices"]
                if not isinstance(devices, list) or not devices or any(isinstance(item, bool) or not isinstance(item, int) or item < 0 for item in devices):
                    errors.append(f"{label}.npu_devices must be a non-empty physical-ID list")
                elif devices != sorted(set(devices)):
                    errors.append(f"{label}.npu_devices must contain unique ascending physical IDs")
        if topology["mode"] == "single_node" and topology["node_count"] != 1:
            errors.append("single_node topology requires node_count=1")
        if topology["mode"] == "multi_node" and topology["node_count"] < 2:
            errors.append("multi_node topology requires at least two nodes")

    paths = data["paths"]
    if exact_keys(paths, {"model", "train_dataset", "eval_dataset"}, "paths", errors):
        absolute_path(paths["model"], "paths.model", errors)
        absolute_path(paths["train_dataset"], "paths.train_dataset", errors)
        if paths["eval_dataset"] is not None:
            absolute_path(paths["eval_dataset"], "paths.eval_dataset", errors)

    workload = data["workload"]
    if exact_keys(workload, {"steps", "batch_sizes", "rollout_count", "tensor_parallel_size", "seed"}, "workload", errors):
        positive_int(workload["steps"], "workload.steps", errors)
        positive_int(workload["rollout_count"], "workload.rollout_count", errors)
        positive_int(workload["tensor_parallel_size"], "workload.tensor_parallel_size", errors)
        if isinstance(workload["seed"], bool) or not isinstance(workload["seed"], int) or workload["seed"] < 0:
            errors.append("workload.seed must be a non-negative integer")
        batch_sizes = workload["batch_sizes"]
        if not isinstance(batch_sizes, dict) or not batch_sizes:
            errors.append("workload.batch_sizes must contain every named batch-size field")
        else:
            for key, value in batch_sizes.items():
                if not isinstance(key, str) or not SAFE_ID.fullmatch(key):
                    errors.append(f"workload.batch_sizes.{key} has an invalid field name")
                positive_int(value, f"workload.batch_sizes.{key}", errors)

    metrics = data["metrics"]
    if exact_keys(metrics, {"performance", "reward_metric", "reward_policy"}, "metrics", errors):
        performance = metrics["performance"]
        if not isinstance(performance, list) or not performance:
            errors.append("metrics.performance must be non-empty")
        else:
            for index, metric in enumerate(performance):
                label = f"metrics.performance[{index}]"
                if exact_keys(metric, {"name", "unit", "window"}, label, errors):
                    for field in ("name", "unit", "window"):
                        non_placeholder(metric[field], f"{label}.{field}", errors)
        non_placeholder(metrics["reward_metric"], "metrics.reward_metric", errors)
        if metrics["reward_policy"] != "report_only":
            errors.append("metrics.reward_policy must be report_only")

    optimization = data["optimization"]
    if exact_keys(optimization, {"objective", "allowed_differences"}, "optimization", errors):
        non_placeholder(optimization["objective"], "optimization.objective", errors)
        differences = optimization["allowed_differences"]
        if not isinstance(differences, list) or not differences or any(not non_placeholder(item, "optimization.allowed_differences item", errors) for item in differences):
            errors.append("optimization.allowed_differences must be non-empty")

    launcher = data["launcher"]
    if exact_keys(launcher, {"exact_override", "runner_may_select"}, "launcher", errors):
        override = launcher["exact_override"]
        authority = launcher["runner_may_select"]
        if override is not None:
            non_placeholder(override, "launcher.exact_override", errors)
        if not isinstance(authority, bool) or (override is None) == (not authority):
            errors.append("choose exactly one launcher override or Runner selection authority")

    policies = data["policies"]
    if exact_keys(policies, {"resume_policy", "resume_source", "step_result_policy", "max_attempts"}, "policies", errors):
        if policies["resume_policy"] not in {"fresh_start", "explicit_resume"}:
            errors.append("policies.resume_policy is invalid")
        if policies["resume_policy"] == "fresh_start" and policies["resume_source"] is not None:
            errors.append("fresh_start forbids resume_source")
        if policies["resume_policy"] == "explicit_resume":
            absolute_path(policies["resume_source"], "policies.resume_source", errors)
        if policies["step_result_policy"] not in {"final_only", "per_step_explicit"}:
            errors.append("policies.step_result_policy is invalid")
        positive_int(policies["max_attempts"], "policies.max_attempts", errors, maximum=100)

    actions = data["authorized_actions"]
    if not isinstance(actions, list) or not actions or any(not non_placeholder(item, "authorized_actions item", errors) for item in actions):
        errors.append("authorized_actions must be a non-empty list")

    if not errors:
        print("intake_valid: true")
        print(f"intake_sha256: {hashlib.sha256(raw).hexdigest()}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("intake_json", type=Path)
    parser.add_argument("--allow-existing-workspace", action="store_true")
    parser.add_argument("--allow-stale-confirmation", action="store_true")
    args = parser.parse_args()
    errors = validate(args.intake_json, args.allow_existing_workspace, args.allow_stale_confirmation)
    if errors:
        for error in errors:
            print(f"intake error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
