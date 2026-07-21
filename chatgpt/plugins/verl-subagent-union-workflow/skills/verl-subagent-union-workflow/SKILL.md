---
name: verl-subagent-union-workflow
description: Run the local Codex five-role VERL Baseline-versus-Optimized workflow on Ascend NPUs. Use only when the user explicitly invokes this skill or explicitly asks to run this workflow.
---

# Local Codex VERL multi-agent workflow

Operate as the main-thread controller. Use Codex native custom agents from `.codex/agents/`. Do not perform Baseline, Optimized, supervision, comparison, or reporting work in the main thread.

## Roles

Use exactly these durable phase roles:

1. `baseline_runner`
2. `workflow_supervisor`
3. `optimized_runner`
4. `workflow_supervisor`
5. `benchmark_comparator`
6. `experiment_reporter`

Use the Supervisor only after a Runner has returned its terminal result. Do not insert a Supervisor review between Runner retry attempts. Each Runner owns preparation, launch, monitoring, diagnosis, minimum repair, verification, retry, and task-owned cleanup in one long-lived agent thread.

Only the main controller interacts with the user. Every subagent is non-interactive, returns blockers to the controller, and must not create another agent.

## Complete intake gate

Before creating or modifying a workspace, work order, container, Ray cluster, training script, source file, or process, present one consolidated checklist. Read-only discovery may suggest candidates, but neither history nor memory confirms a value for the user.

The controller must serialize the checklist as intake JSON and run the bundled `scripts/validate_intake.py` before any mutation. The validator rejects missing/extra fields, placeholders, stale confirmations, an existing workspace, invalid private addresses, and non-canonical physical NPU lists. The gate wrapper must receive the exact node-local list through `--npu-devices`; it validates count, uniqueness, inherited visible-device variables, and launch-time `ASCEND_RT_VISIBLE_DEVICES`/`NPU_VISIBLE_DEVICES` binding. A multi-node `expected_npus` value is the total and is divided evenly across nodes.

Confirm all of the following together:

- run ID and a new absolute workflow workspace;
- Baseline and Optimized container names, image/runtime plan, source roots, and whether missing containers may be created;
- topology, node count, private address per node, and exact physical NPU allocation per node;
- absolute model, train dataset, and optional eval dataset paths;
- training steps, every batch-size field, rollout count, tensor parallel size, and seed;
- performance metrics, units, aggregation window, reward metric, and reward comparison policy;
- optimization objective and every permitted Baseline/Optimized difference;
- exact launcher override or authority for the Baseline Runner to select or generate it;
- `resume_policy`, `step_result_policy`, `max_attempts`, and authorized actions.

When the user does not explicitly choose another VERL image, use the local image archive `/mnt/disk2t/l30002999/images/verl-0.7.1_vllm-0.18.0_cann-8.5.1_baseline-installed.tar`; do not infer the image from an existing container name or tag. Every new Ascend/VERL role container mounts and verifies both `/mnt/disk2t` and `/mnt/sfs_turbo`.

Propose these local defaults, but require confirmation:

```text
resume_policy=fresh_start
step_result_policy=final_only
max_attempts=20
```

`final_only` means native training logs plus terminal/aggregate results only. It forbids extra per-step results, checkpoints, snapshots, Project Memory entries, Experience Vault entries, and project archives. Only an explicit current-run user override can enable per-step persistence.

`fresh_start` forbids inferred or restored launcher, step, checkpoint, optimizer, metric, Ray-session, and output state from previous runs. An explicit resume source must be confirmed as part of a new work order.

Project summaries, project memory, and project-specific archives are path-scoped. Do not import them from another project as workflow inputs. Only separately distilled, anonymized, verified cross-project knowledge may be reused.

End the checklist with the exact token `CONFIRM_COMPLETE_INTAKE`. Do not treat generic confirmation, partial confirmation, an older run, or a previous work order as complete intake.

Materialize the confirmed values as JSON matching `scripts/validate_intake.py`, and run that validator before the first mutation. A missing field, placeholder, stale confirmation, existing workspace, non-RFC1918 node address, or non-canonical physical-NPU list blocks execution.

If base data, model, workspace, topology, NPU allocation, or experiment semantics are still missing, the main controller asks the user. Subagents never ask.

## Immutable work order

After complete confirmation, write one immutable work order under the confirmed controller workspace. It contains only confirmed execution inputs. A changed model, dataset, workspace, objective, topology, resource allocation, workload field, resume policy, persistence policy, or optimization allowlist requires a new run and new workspace.

After intake, the workflow independently decides implementation details inside the confirmed scope: container preparation, Ray and private-network setup, launcher/config realization, compatibility repair, retry, and task-owned cleanup do not require more user interaction.

## Dispatch and resource isolation

Dispatch phase agents from the main thread only. Subagents do not spawn, delegate, or interact with the user.

Baseline and Optimized execute sequentially on the same confirmed allocation by default. Parallel execution is allowed only when the user confirmed disjoint node/NPU allocations.

For a confirmed physical NPU 8-15 run:

- launch and cleanup are limited to physical NPU 8-15;
- never stop, kill, clean, restart, or reuse a Ray/process/container state that belongs to physical NPU 0-7;
- cleanup requires evidence that the target process belongs to the current run and assigned role container;
- foreign or ambiguous occupancy produces a blocker instead of cleanup.

Every gate-wrapper invocation supplies `--npu-devices` with the exact node-local physical IDs. The wrapper binds that value to the immutable work order and Actor private IP, rejects conflicting inherited visible-device variables or training arguments, and exports both `ASCEND_RT_VISIBLE_DEVICES` and `NPU_VISIBLE_DEVICES` before launch. NPU count alone is never sufficient.

The training script and configuration for single-node and multi-node comparisons keep the same workload fields. Only topology, node/Ray networking, role/output paths, confirmed resource mapping, and explicitly approved optimization differences may vary.

## Phase order

For every requested topology:

1. Dispatch `baseline_runner` and wait for its terminal result.
2. Dispatch `workflow_supervisor` for one read-only terminal review.
3. Dispatch `optimized_runner` only after Baseline success and proven cleanup.
4. Dispatch `workflow_supervisor` for one read-only terminal review.
5. Dispatch `benchmark_comparator` only after both compatible terminal results exist.
6. Dispatch `experiment_reporter` after the comparison is complete.

If the user pauses the task, stop or interrupt only current-workflow agents and processes whose ownership is proven. Then verify no owned training or Ray process remains. Do not touch unrelated work.

## Results

Each phase returns one concise terminal result with status, primary artifact/log path, blocker if any, and next action. Keep raw and dense output in native files. Do not create a separate artifact for every training step or retry.

The comparator reports:

- mean step time and delta;
- throughput and delta;
- reward value and delta;
- workload comparability and evidence paths.

Reward values and deltas are report-only. Do not decide whether reward behavior is reasonable; that judgment belongs to the user.

## Git and patch boundary

When source optimization is part of the confirmed run, use local Git in the Optimized source tree and keep Baseline source unchanged. Archive approved source differences as reviewable patches. Do not import customer-specific code wholesale; preserve source-native behavior that is relevant and keep the approved optimization semantics equivalent.

Git operations for this workflow are local and offline. Do not fetch, pull, push, or perform equivalent code-sync network operations.

Local Git means inspection, commits, and patch generation only. Do not fetch, pull, push, or perform any equivalent network synchronization unless the user explicitly authorizes that operation in the current turn.
