---
name: verl-subagent-union-workflow
description: Explicit-only Codex plugin workflow controller for VERL + Ascend/NPU multi-subagent optimization. Use only when the user explicitly invokes this plugin or this skill with @ or $, not for ordinary VERL/NPU requests.
---

# VERL Subagent Union Workflow For Codex

This skill is the explicit controller entrypoint for the Codex plugin `verl-subagent-union-workflow`.

Do not implicitly activate this workflow. It is intended to run only when the user explicitly invokes the plugin or skill from Codex.

## Controller Boundary

The current assistant is the main workflow controller. It coordinates specialized Codex subagents, persists phase artifacts, and enforces supervisor gates. It must not perform phase-worker duties itself.

If the controller is about to inspect bulky logs, validate an environment, run training, edit optimization code, compare metrics, debug a failure, or write a final experiment report, it must spawn the matching workflow agent instead.

Allowed controller work:

- intake and missing-input questions
- project/workspace discovery and confirmation
- phase-state, work-order, delegation, session, change-ledger, and supervisor-verdict bookkeeping
- spawning the matching Codex custom agent
- waiting for and summarizing bounded subagent results
- blocking a phase when routing or required evidence is invalid

## Codex Agent Dispatch

Use Codex subagents, not OpenCode `task()` calls.

The workflow agents are repo-scoped Codex custom agents under `.codex/agents/*.toml`. Codex custom-agent names must use lowercase letters, digits, and underscores, so the Codex roles use underscores even though the original OpenCode files use hyphens. Before dispatch, verify the requested role is in the allowlist below. Spawn exactly the role required for the current phase, and treat any missing or wrong-role result as invalid evidence.

Never substitute Codex built-in agents (`default`, `explorer`, or `worker`) for a workflow role. If the requested workflow role cannot be spawned as that exact custom agent, stop with `routing_blocker: phase_agent_required`.

When dispatching, tell the subagent:

- the expected phase and role
- the run id, topology, work-order path, and relevant artifact paths
- the exact allowed and forbidden actions
- to return bounded summaries and artifact paths, not raw logs or dense output
- to preserve evidence under `runs/{run-id}/`

Do not let phase agents directly hand off to each other. The controller receives each result, then spawns `workflow-supervisor` to audit it before advancing.

## Active Agents

Allowed workflow roles:

```text
optimization_analyst
workflow_supervisor
context_curator
verl_npu_env_builder
source_release_manager
baseline_runner
optimization_implementer
optimized_runner
benchmark_comparator
run_evidence_analyst
workflow_generalist
debug_isolator
experiment_reporter
```

Role routing:

- `optimization_analyst`: optimization idea intake, solution analysis, risk review, and bounded code/file mapping.
- `verl_npu_env_builder`: environment readiness, containers, CANN, torch_npu, model/data/script path checks, and environment checkpoints.
- `source_release_manager`: GitHub branch, local worktree, commit, cleanliness, publication, and runtime switch contract gates for GitHub-backed worktree stacks.
- `baseline_runner`: baseline readiness, launch gate, durable execution, log polling, and baseline checkpoint.
- `optimization_implementer`: smallest approved core implementation patch after a successful baseline.
- `optimized_runner`: optimized readiness, launch gate, durable execution, log polling, and optimized checkpoint.
- `benchmark_comparator`: same-topology baseline/optimized comparison and verdict.
- `run_evidence_analyst`: bulky log, profiler, metric, and training-output inspection in isolation.
- `debug_isolator`: failed-phase root cause isolation and retry routing.
- `context_curator`: context hygiene and recoverable handoff summaries.
- `workflow_supervisor`: transition gate audit after every phase result.
- `experiment_reporter`: final report and archive manifest from approved evidence.
- `workflow_generalist`: small workflow-support tasks only when no specialist applies.

## Phase Gates

Default phase order:

```text
optimization_analyst
-> workflow_supervisor
-> context_curator
-> verl_npu_env_builder
-> workflow_supervisor
-> source_release_manager
-> workflow_supervisor
-> baseline_runner
-> workflow_supervisor
-> optimization_implementer
-> workflow_supervisor
-> source_release_manager
-> workflow_supervisor
-> optimized_runner
-> workflow_supervisor
-> benchmark_comparator
-> workflow_supervisor
-> experiment_reporter
```

For multi-topology experiments, complete each topology pair before starting the next:

```text
single-node baseline+optimized+comparison
-> dual-node baseline+optimized+comparison
-> four-node baseline+optimized+comparison
```

The next topology is allowed only after the current topology has a successful baseline, successful optimized run, comparison checkpoint, and supervisor approval, unless the user explicitly records a skip.

## Artifact Requirements

Before each phase dispatch, create or update a work-order under `runs/{run-id}/`.

After each phase result, persist a bounded delegation result with:

- `delegation_id`
- expected agent and actual agent
- phase
- terminal status
- summary
- primary artifact path
- evidence paths
- blocker, if any
- proposed next action

Do not approve phase transitions from chat-only output. Require persisted artifact paths, especially for training, implementation, comparison, debug, and final reporting.

## Routing Blockers

Block and do not advance when any of these conditions occur:

- `phase_agent_required`: the controller is about to do phase-worker work or a required agent is unavailable.
- `non_workflow_agent`: the selected role is outside the allowlist.
- `main_agent_substitution`: the result does not prove a specialized workflow agent ran.
- `archive_gate_required`: a verified root cause/fix lacks archive review.
- `source_release_gate_required`: baseline or optimized source checkpoint is missing, unapproved, dirty, branch-mismatched, unpublished when publication is required, or inconsistent with the runtime switch contract.
- `preflight_gate_required`: runner preflight artifacts are missing or invalid.
- `direct_training_launch`: training was launched outside the workspace gate wrapper.
- `direct_runtime_switch`: source was copied into the runtime tree outside the approved worktree stack switch script.
- `log_polling_required`: runner-side polling artifacts are missing.
- `runner_preflight_failed`: baseline or optimized launch preflight failed, is missing, or is unknown.
- `topology_order_violation`: a larger topology starts before the current pair is complete.

For any routing blocker, discard the returned phase output as invalid evidence. Report the blocker and repair path; do not complete the phase yourself.

## GitHub-Backed Worktree Stack Mode

Use this mode when a VERL project stores orchestration on a management branch and stores baseline and optimized full source trees on separate GitHub branches backed by local git worktrees. A project enters this mode when the work-order provides `source_release` and `worktree_stack`, or when project discovery finds `stack.json`, `scripts/switch_stack.py`, and `scripts/trainctl.py`.

In this mode GitHub is the publication and restore source of truth, local worktrees are the source trees, and the container runtime tree is only a synchronized runtime target. The workflow must prove consistency across all three layers before training:

- GitHub branches and local worktrees: verified by `source_release_manager`.
- Runtime target such as `/vllm-workspace/verl`: selected only by the approved switch script.
- Training launch: started only by the approved gate wrapper, normally `scripts/trainctl.py`.

The controller must include these fields in the work-order before dispatching source, runner, implementation, or comparison phases:

```yaml
source_release:
  remote: "<git remote url>"
  sync_policy: "verify_only|pull_allowed|push_allowed|full_sync_allowed"
  management:
    branch: "<management branch>"
    worktree: "<management worktree>"
  baseline:
    branch: "<baseline branch>"
    worktree: "<baseline source worktree>"
    immutable: true
  optimized:
    branch: "<optimized branch>"
    worktree: "<optimized source worktree>"
    publish_required_before_run: true
worktree_stack:
  enabled: true
  stack_root: "<path containing stack.json>"
  inventory: "<inventory path>"
  nodes: "1|2|4"
  variants:
    baseline: "baseline"
    optimized: "optimized-v4"
  runtime_target: "/vllm-workspace/verl"
```

Workflow agents must not collapse baseline and optimized behavior into one runtime source tree, must not use environment variables as the baseline/optimized switch, and must not manually copy arbitrary source files into the runtime target. If `trainctl.py` exists, runners must use it; direct invocation of variant `container_train_*.sh` is invalid unless the work-order explicitly names a different gate wrapper.

`source_release_manager` must produce `runs/{run-id}/source/source-checkpoint.yaml` before baseline or optimized runner phases. The checkpoint must record management, baseline, and optimized commits; branch names; worktree cleanliness; publication status allowed by `sync_policy`; baseline optimization-code absence; optimized-code presence; and the exact runtime switch and train wrapper contract that downstream agents must use.

## Verified RCA Archive Gate

Any workflow subagent that identifies a root cause, applies or recommends a fix, and verifies the fix must complete Experience Vault archive review before the controller advances.

Required fields in subagent output after verified RCA:

```yaml
archive_gate:
  verified_root_cause: true
  fix_verified: true
  archive_review_done: true
  archive_command: "<machine-appropriate Experience Vault milestone/review command, if Experience Vault is available>"
  archive_decision: archived | draft_created | no_archive_needed
  archive_artifacts: []
```

Do not archive a hypothesis as reusable experience. This gate starts only after the fix is verified.

## Safety

Keep raw logs, full tracebacks, credentials, private IPs, profiling dumps, full diffs, install logs, and large artifacts out of the main context. Use paths and concise summaries.

When an Ascend/NPU container action is involved, follow the user's active Ascend/Docker rules, including required shared mounts when creating containers.

## OpenCode Compatibility Note

This Codex plugin replaces OpenCode `task(subagent_type=...)` dispatch with Codex custom-agent dispatch. The original OpenCode workflow remains in `verl-subagent-union-workflow/` for users who still run OpenCode.
