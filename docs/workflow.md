# Codex VERL workflow contract

## Authority

This contract mirrors the active local Codex workflow. It does not import assumptions, roles, artifacts, or state from the former project implementation.

## Required intake

Before any workspace, container, Ray, training, cleanup, or source mutation, the main controller presents one complete checklist and receives one complete confirmation. The checklist fixes:

- run ID and a fresh absolute workflow workspace;
- Baseline and Optimized container names, image/runtime plan, source roots, and creation permission;
- topology, nodes, private addresses, and exact physical NPU allocation per node;
- absolute model, train dataset, and optional eval dataset paths;
- steps, batch sizes, rollout count, tensor parallel size, seed, and launcher decision;
- metrics, units, aggregation window, reward metric, and reward policy;
- optimization objective and the complete allowlist of Baseline/Optimized differences;
- fresh-start/resume policy, final-only/per-step persistence policy, authorized actions, and `max_attempts`.

The controller may propose `max_attempts=20`, `resume_policy=fresh_start`, and `step_result_policy=final_only`, but they become valid only after user confirmation. Missing base paths or experiment semantics must be resolved by the main controller. Subagents never ask the user.

The controller writes the confirmed intake as JSON and runs the bundled `validate_intake.py` before any mutation. The runtime gate receives the exact node-local `--npu-devices` list, binds it to the immutable work order and Actor private IP, and exports matching Ascend visible-device variables. Supplying only an NPU count cannot authorize launch.

If the user does not select another image, container creation uses `/mnt/disk2t/l30002999/images/verl-0.7.1_vllm-0.18.0_cann-8.5.1_baseline-installed.tar`. Do not infer an image from an existing container name/tag. Every new role container mounts and verifies `/mnt/disk2t` and `/mnt/sfs_turbo`.

## Execution

1. Create a fresh canonical workspace and immutable work order.
2. Run `baseline_runner`; it owns diagnosis, minimum repair, retry, and cleanup through the terminal result.
3. Run `workflow_supervisor` once on the terminal Baseline result.
4. Run `optimized_runner` with the Baseline workload fields preserved except for approved differences.
5. Run `workflow_supervisor` once on the terminal Optimized result.
6. Run `benchmark_comparator` and then `experiment_reporter`.

Baseline and Optimized run sequentially on the same confirmed NPU allocation unless the user explicitly confirms disjoint resources. For a back-eight-card run, no role may stop, clean, restart, or otherwise affect front-eight-card processes. Cleanup requires proof that the process belongs to the current run and target role container.

After intake, container, Ray, network, launcher, compatibility repair, retry, and task-owned cleanup decisions are autonomous within the confirmed boundaries. A subagent returns a blocker only when it must change a confirmed model/dataset/workspace/objective, lacks external authority, or cannot distinguish task-owned state safely.

## Evidence and persistence

- Do not infer or restore launcher, step, checkpoint, optimizer, metric, Ray-session, or output state from an earlier run.
- Do not import another project's summaries, project memory, or project-specific archives as run inputs.
- Default to native training logs plus one terminal/aggregate result per phase.
- Do not create per-step result, checkpoint, snapshot, Project Memory, Experience Vault, or project-archive records unless the user explicitly enables them for this run.
- Keep raw logs by path; do not flood controller context with dense output.
- Reward comparison reports values and deltas only. The user decides whether reward behavior is reasonable.

## Agent isolation

Only the main controller may interact with the user or dispatch roles. All five phase roles are non-interactive and may not spawn or delegate to nested agents. A role returns one concise terminal result to the controller.

Codex custom-agent non-interaction and no-nesting are instruction boundaries validated from the five role definitions; Codex does not expose a separate per-agent tool sandbox in this repository.
