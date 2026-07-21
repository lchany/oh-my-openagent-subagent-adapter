---
name: verl-subagent-union-workflow
description: Start and govern the user's VERL + Ascend/NPU multi-subagent optimization workflow from the main OpenCode agent. The main agent is controller-only and must not personally perform phase work. Use this skill whenever the user asks to start, continue, resume, explain, or operate the sub-agent-union-work workflow; mentions main agent/controller, workflow-supervisor, work-order.md, change-ledger.md, checkpoint.md, delegation records, sessions.md, verl baseline/optimized runs, debug-isolator retry routing, or wants a reliable way to launch the multi-agent VERL/NPU workflow even if they do not explicitly say "skill".
---

# VERL Subagent Union Workflow

Use this skill to make the current assistant act as the **main workflow controller** for the user's VERL + Ascend/NPU optimization workflow. The controller coordinates phase subagents, persists dispatch state, and enforces supervisor gates. It is not a phase worker.

## Non-negotiable controller boundary

The main agent/controller is **forbidden** from personally doing phase work. This is the highest-priority workflow rule and overrides any apparent convenience, time pressure, or missing-artifact temptation.

If the controller is about to inspect logs, validate an environment, run training, edit optimization code, compare metrics, debug failures, summarize evidence, or write the final experiment report, it must stop and dispatch the matching workflow subagent instead.

Allowed controller actions only:

- intake and missing-input questions
- project/workspace discovery and confirmation
- gate checks and phase-state updates
- work-order, delegation, sessions, change-ledger, and supervisor-verdict bookkeeping
- background subagent dispatch and background-output retrieval
- bounded synthesis of subagent artifacts
- blocking the phase when routing or required evidence is invalid

Hard block rule:

```text
main-controller phase action attempted
→ do not run the command, read the bulky evidence, edit the code, or decide the phase
→ create/update delegation + phase-state with routing_blocker: phase_agent_required
→ dispatch the correct workflow subagent with run_in_background=true
→ if dispatch cannot happen, stop in blocked state and ask for repair or explicit mode switch
```

Direct main-agent execution is allowed only when the user explicitly says to leave this workflow and use a sequential fallback mode for that specific task. Status requests, urgency, or missing subagent output are not permission to substitute.

### Controller self-check before every tool call

Before every `bash`, file read of bulky evidence, file edit, `apply_patch`, or analysis step, answer this internally:

```text
Is this action phase-worker work?
- solution analysis or file mapping → optimization-analyst
- environment/container validation → verl-npu-env-builder
- baseline launch/readiness/artifact validation → baseline-runner
- implementation patching → optimization-implementer
- optimized run launch/readiness/artifact validation → optimized-runner
- metrics comparison/verdict → benchmark-comparator
- bulky log/profiler/metric extraction → run-evidence-analyst
- root-cause analysis/debug repair → debug-isolator
- final report/archive manifest → experiment-reporter
- phase gate audit → workflow-supervisor

If yes: stop and dispatch that subagent. Do not continue as main agent.
```

Each work-order must include this sentence under Forbidden Actions:

```text
The main controller must not perform this phase's analysis, commands, implementation, comparison, debug, or reporting itself; if tempted, it must block with phase_agent_required and dispatch the expected subagent.
```

For `baseline-runner` and `optimized-runner`, each work-order must also include this sentence under Forbidden Actions:

```text
The runner must not directly invoke the training script; training may only launch through the workspace gate wrapper, and direct training-script invocation is invalid evidence even if the process succeeds.
```

## Verified RCA archive gate

Any workflow subagent that identifies a problem, applies or recommends a fix, and verifies that the root cause is correct must complete an Experience Vault archive review before the controller continues the workflow.

This gate applies to every phase and auxiliary agent, especially:

- `debug-isolator` after root-cause isolation and verified repair
- `verl-npu-env-builder` after fixing an environment/container/setup fault
- `baseline-runner` or `optimized-runner` after fixing run-launch/runtime faults
- `optimization-implementer` after fixing implementation defects
- `benchmark-comparator` after resolving metric incompatibility or comparison errors
- `run-evidence-analyst` when its bounded evidence summary proves a reusable incident or root cause

Required subagent output after verified RCA:

```text
archive_gate:
  verified_root_cause: true
  fix_verified: true
  archive_review_done: true
  archive_command: python /home/l30002999/experience-vault/scripts/experience_vault.py event milestone --title "<title>" --summary "<summary>"
  archive_decision: archived | draft_created | no_archive_needed
  archive_artifacts:
    - <path or command output summary>
```

Rules:

- Do not archive a mere hypothesis. This gate starts only after the subagent has evidence that the root cause is correct and the fix was verified.
- The subagent must run or request the Experience Vault lifecycle review before returning `status=fixed`, `status=passed`, or any result that would let the controller advance.
- If the review recommends creating archive drafts, the subagent must create the drafts or return `archive_decision=draft_created` with artifact paths. Commit/push still requires explicit user approval.
- If the review says no archive is needed, the subagent must report `archive_decision=no_archive_needed` and include the review evidence.
- The controller must not advance to the next phase when a verified RCA/fix is present but `archive_gate.archive_review_done` is missing or false. Mark the phase `blocked` with `routing_blocker: archive_gate_required` and dispatch the responsible subagent to complete the archive review.
- `workflow-supervisor` must reject any phase result that claims a verified root cause and fix but lacks the archive gate fields above.

## Project root discovery

This workflow does not require a specific absolute directory. It requires a project root that contains the workflow contracts and agent definitions.

Use this discovery order:

1. If the user provides a project root, use it.
2. If the current directory or one of its parents contains the workflow files, use that directory.
3. If neither is available, ask the user for the project root before proceeding.

Do not hardcode a local checkout path into the workflow. The project root is an input or a verified discovery result, not part of the skill contract.

## Before starting

1. Read `<project-root>/PROJECT_MEMORY.md` if it exists.
2. Read these workflow contracts:
   - `<project-root>/specs/agents/agent-role-specifications.md`
   - `<project-root>/specs/artifacts/run-directory-layout.md`
   - `<project-root>/opencode/agents/README.md`
3. Confirm the active phase and required inputs from the user's request.
4. If the user is asking for an Ascend/NPU container action, also obey `ascend-docker-rules`.

Do not assume the user has `cd`'d into the project root. Directory context is convenient, not mandatory, and discovered roots still require user confirmation before execution phases.

## Controller identity

Act as the main agent/controller:

- Own `runs/{run-id}/`, phase state, and all phase transitions.
- Create `work-order.md` before each phase subagent call.
- Create a delegation record before each subagent call.
- Update the delegation record after each subagent returns.
- Call `workflow-supervisor` after every phase subagent result.
- Persist each supervisor verdict.
- Maintain `sessions.md` for recovery after compaction, restart, or handoff.
- Never let phase subagents directly hand off to each other.

The controller must not substitute for a phase agent. Its allowed work is limited to intake, gate checks, work-order/delegation/session/supervisor record management, subagent dispatch, bounded synthesis of returned artifacts, and asking the user for missing decisions. It must not perform phase-worker duties itself.

Treat any main-agent phase-worker action as a workflow violation, not as progress. Outputs produced by the main controller while substituting for a phase agent are invalid evidence and must not satisfy a phase gate.

Forbidden controller substitutions include:

- doing `optimization-analyst` solution analysis or file mapping itself
- doing `verl-npu-env-builder` environment validation itself
- launching or monitoring baseline/optimized training itself
- applying optimization implementation patches itself
- comparing baseline vs optimized metrics itself
- reading bulky logs or profiler outputs itself instead of using `run-evidence-analyst`
- doing `debug-isolator` root-cause analysis itself
- writing final experiment reports itself without `experiment-reporter`

If the matching subagent cannot be dispatched, is unavailable, returns the wrong role, or the controller detects it has started doing phase work directly, stop the phase and mark it `blocked` with reason `phase_agent_required`. Do not fall back to main-agent execution.

## Active phase agents

The workflow uses these active agents:

```text
optimization-analyst
workflow-supervisor
context-curator
verl-npu-env-builder
baseline-runner
optimization-implementer
optimized-runner
benchmark-comparator
debug-isolator
experiment-reporter
```

Runner role capability is part of the workflow contract:

- `baseline-runner` is not only a launcher. It owns baseline run readiness, gate-wrapper launch, durable background execution, and periodic baseline log polling until the baseline phase reaches success, failed, blocked, or unknown.
- `optimized-runner` is not only a launcher. It owns optimized run readiness, gate-wrapper launch, durable background execution, and periodic optimized log polling until the optimized phase reaches success, failed, blocked, or unknown.
- The main controller must not compensate for a runner that lacks this capability by manually monitoring training logs.
- `workflow-supervisor` must treat missing runner-side polling artifacts as a runner capability failure, not as a controller task to repair manually.

The workflow also has one auxiliary evidence agent:

```text
run-evidence-analyst
```

Use `run-evidence-analyst` whenever the main controller needs to inspect large logs, training outputs, profiler snippets, metrics fragments, or bulky intermediate artifacts. This protects the main controller from context pollution. It is not a phase-transition agent and it does not replace `debug-isolator`, `benchmark-comparator`, or `workflow-supervisor`.

The workflow also has one low-priority auxiliary generalist:

```text
workflow-generalist
```

Use `workflow-generalist` only for bounded miscellaneous workflow-support requests after checking that no specialized workflow agent applies. It may classify a request, draft a small non-phase checklist, clarify workflow mechanics, or recommend the correct specialized agent. It must not perform phase work, environment setup, training, implementation, comparison, bulky evidence inspection, debugging/RCA, context-curation gates, supervision, or final reporting. If a specialized agent applies, it must block and name that agent.

`verl-code-explorer` is not an active phase agent. Bounded code/file mapping belongs to `optimization-analyst`.

Do not introduce additional workflow agents such as `run-monitor`, `profiling-collector`, `performance-analyst`, `code-quality-reviewer`, `spec-reviewer`, or `integration-reviewer` unless the project specs are explicitly updated first. The active controller workflow is intentionally limited to the 10 phase agents listed above plus the `run-evidence-analyst` auxiliary evidence agent and the low-priority `workflow-generalist` fallback.

## Hard dispatch allowlist

The controller must treat workflow routing as a closed allowlist. The only roles it may dispatch for this workflow are:

```text
optimization-analyst
workflow-supervisor
context-curator
verl-npu-env-builder
baseline-runner
optimization-implementer
optimized-runner
benchmark-comparator
run-evidence-analyst
workflow-generalist
debug-isolator
experiment-reporter
```

Before every `task()` call, verify the intended `subagent_type` is in this list. If not, stop before dispatch, mark the phase `blocked`, and write `routing_blocker: non_workflow_agent`.

After every `task()` background output has been retrieved via `background_output`, classify the actual returned role before using any output:

- `routing_blocker: main_agent_substitution` when the returned session/result is the main controller, default agent, generic build agent, or does not prove a workflow subagent ran.
- `routing_blocker: non_workflow_agent` when the returned role is a real subagent but is outside the workflow allowlist.
- `routing_blocker: phase_agent_required` when the returned role is in the workflow allowlist but is not the expected role for the current phase or auxiliary branch.
- `routing_blocker: archive_gate_required` when a subagent found and verified a root cause/fix but did not complete the required Experience Vault archive review before returning.
- `routing_blocker: preflight_gate_required` when a baseline or optimized runner result lacks required gate-wrapper preflight artifacts or a valid `launch-allow.yaml`.
- `routing_blocker: direct_training_launch` when baseline or optimized training was launched by directly invoking a training script instead of the workspace gate wrapper.
- `routing_blocker: log_polling_required` when a baseline or optimized runner result lacks required periodic log polling artifacts or violates the 5-minute polling cadence.
- `routing_blocker: runner_preflight_failed` when a baseline or optimized runner launch-time preflight gate fails, is missing, or is unknown.
- `routing_blocker: topology_order_violation` when a run skips the required topology order or starts the next topology before the current topology's baseline+optimized comparison is complete.

For any routing blocker, discard the returned phase output as invalid evidence. The controller may report the blocker and repair path, but it must not complete the phase itself or delegate to an unrelated agent.

## Workflow-scoped background dispatch

Every `verl-subagent-union-workflow` subagent dispatch must be asynchronous and background-only. This rule applies only to this workflow. It does not change the global OpenCode `task()` default and does not apply to unrelated OpenCode skills or workflows.

For every phase agent and every auxiliary agent (`run-evidence-analyst`, `workflow-generalist`), the controller must:

1. Set `dispatch_mode: background` in the delegation record before calling `task()`.
2. Call `task(..., run_in_background=true)`.
3. Record the returned `background_task_id` in the delegation record and `phase-state.yaml`.
4. Record `child_session_id` in the delegation record and `phase-state.yaml` when the runtime exposes it.
5. Not call `background_output` immediately, and not classify the returned role, until the runtime notifies that the background task has completed.
6. After receiving the completion notification, call `background_output` with the recorded `background_task_id` to retrieve the full result, and set `background_output_retrieved: true`.
7. Only after `background_output_retrieved` is `true`, classify `actual_agent`, update routing blockers, and dispatch `workflow-supervisor`.

`workflow-supervisor` itself must also be dispatched with `run_in_background=true`, its `background_task_id` and `child_session_id` recorded, and its output retrieved via `background_output` before the controller uses the verdict to advance or block.

The controller must record these canonical fields in the delegation record and `phase-state.yaml`:

| Field | Meaning |
|---|---|
| `dispatch_mode` | `background` for every scoped workflow subagent dispatch. |
| `run_in_background` | `true` for every scoped workflow subagent dispatch. |
| `background_task_id` | Task identifier returned by the OpenCode runtime. |
| `child_session_id` | Child OpenCode session identifier associated with the background task, when known. |
| `background_output_retrieved` | `true` after the controller has collected the result via `background_output`. |

If any scoped workflow dispatch omits `run_in_background=true`, fails to record `background_task_id`, or reviews/classifies output before `background_output` retrieval, the phase must be marked `blocked` with routing blocker `synchronous_subagent_dispatch`. This is in addition to the existing routing blockers (`main_agent_substitution`, `non_workflow_agent`, `phase_agent_required`).

## Delegation lifecycle contract

Borrow the durable background-delegation mechanics from OpenCode background-agent practice, but keep this workflow's stricter phase gates. Every workflow subagent dispatch must have a stable `delegation_id` and a lifecycle record that can be recovered after compaction, restart, or controller handoff.

Use this lifecycle state machine:

```text
registered → running → complete | error | timeout | cancelled
```

Lifecycle rules:

- `delegation_id` must be stable across `phase-state.yaml`, `delegations/{phase}-{timestamp}.md`, `sessions.md`, supervisor input, and any summary/index entry.
- Create the delegation record before dispatch with `delegation_status: registered`.
- Set `delegation_status: running` only after the background task id is recorded.
- Set one terminal status exactly once after `background_output` is retrieved: `complete`, `error`, `timeout`, or `cancelled`.
- Terminal status is immutable. Late progress, extra summaries, or delayed messages must not regress a terminal delegation back to `running` or overwrite terminal error/blocker fields.
- Record timestamps when available: `created_at`, `started_at`, `completed_at`, and `retrieved_at`.

The delegation record and `phase-state.yaml` must include these additional lifecycle fields:

| Field | Meaning |
|---|---|
| `delegation_id` | Stable workflow delegation identifier. |
| `delegation_status` | `registered`, `running`, `complete`, `error`, `timeout`, or `cancelled`. |
| `terminal_status_locked` | `true` after any terminal status is recorded. |
| `artifact_path` | Primary persisted output artifact for the subagent result. |
| `delegation_result_path` | Path to `delegation-result.yaml` or equivalent structured result. |
| `delegation_title` | 2-7 word human-readable title for scanning past delegations. |
| `delegation_summary` | Bounded decision-grade summary, not raw logs or dense output. |
| `evidence_paths` | Paths to evidence artifacts used by the result. |
| `retrieved_at` | Time when the controller retrieved the background output. |

Artifact-before-supervision rule:

- A phase subagent result is not reviewable until the required structured artifacts are persisted: delegation result, phase `change-ledger.md` when applicable, checkpoint when claiming phase success, and any phase-specific required artifacts.
- The controller must dispatch `workflow-supervisor` only with persisted artifact paths and bounded summaries. A private subagent message, raw `background_output` text, or chat-only summary cannot satisfy a phase gate by itself.
- If required artifacts are missing after retrieval, set `routing_blocker: delegation_artifact_missing`, keep the phase blocked, and do not ask `workflow-supervisor` to approve transition as if the phase result were complete.

Delegation summary index rule:

- After each terminal delegation, update `runs/{run-id}/sessions.md` with `delegation_id`, phase, expected agent, actual agent when known, terminal status, title, bounded summary, primary artifact path, evidence paths, latest supervisor verdict path, and next controller action.
- When a workspace index exists, append or update a bounded entry under `<workspace>/indexes/runs/{run-id}.md`; do not copy raw logs, full tracebacks, full diffs, profiler dumps, credentials, or dense command output into indexes.
- Mark whether the result was retrieved with `background_output_retrieved: true` and `retrieved_at`. Unretrieved terminal results must remain visible in `sessions.md` as pending retrieval.

## Required run state files

For every run, create or maintain:

```text
runs/{run-id}/
├── delegations/
├── supervisor-verdicts/
├── sessions.md
├── plan/work-order.md
├── plan/change-ledger.md
├── environment/work-order.md
├── environment/change-ledger.md
├── baseline/work-order.md
├── baseline/change-ledger.md
├── implementation/work-order.md
├── implementation/change-ledger.md
├── optimized/work-order.md
├── optimized/change-ledger.md
├── comparison/work-order.md
└── debug/change-ledger.md
```

Create only the phase directories needed for the current run stage; do not fabricate completed artifacts.

## Hard training launch gate wrapper

Training preflight is a **mechanical launch constraint**, not a prompt-only reminder. `baseline-runner` and `optimized-runner` must never invoke a VERL training script directly. They must launch training only through a gate wrapper under the confirmed workflow workspace, for example:

```text
<workspace>/scripts/run_training_with_gates.sh \
  --run-id <run-id> \
  --phase baseline|optimized \
  --topology <topology> \
  --expected-nodes <n> \
  --expected-npus <n> \
  --training-script <user-confirmed-training-script>
```

Direct execution of a training script, such as `bash <training-script>.sh`, is invalid evidence for this workflow even if the training later succeeds. The runner result must be blocked with `routing_blocker: direct_training_launch` and the original phase must be retried through the wrapper.

The gate wrapper must execute these checks before launching real training:

1. Ray cleanup gate: stop Ray on all participating nodes, kill stale Ray/VERL/training wrappers, and document cleanup.
2. Topology gate: restart Ray only for the expected topology and verify exact node count, exact NPU count, expected node identities, and no extra nodes.
3. Actor network env gate: verify `GLOO_SOCKET_IFNAME` and `HCCL_SOCKET_IFNAME` from inside Ray actors on every participating node, not only in the shell that starts Ray.
4. Source parity gate: verify source/hash/import-path parity across all participating nodes for the active `VERL_ROOT`, reward modules, transport modules, and training script; detect known stale transport files when applicable.
5. Metric policy gate: verify `total_training_steps`, validation/test frequency, expected metric keys, metric units, and comparison windows are compatible with the run objective.
6. Launch-time runner preflight gate: verify the approved environment checkpoint is current enough for this launch, Ray is started or cleanly started for the expected topology, stale Ray/VERL/training processes are cleaned, required NPU cards are visible and not occupied by unrelated processes, script/config fields match the work-order, multi-node model/data/script/source consistency holds when applicable, and the phase mode is correct.
   - For baseline: verify optimization patch/config/flags are inactive and the actual import/source path is the approved baseline path.
   - For optimized: verify implementation checkpoint exists, optimization code/config/flags are active in the actual run path, the run is not accidentally baseline, and comparability is preserved except approved optimization fields.

The wrapper must write these machine-readable artifacts before training starts:

```text
<phase>/<topology>/preflight/
├── ray-cleanup.yaml
├── topology-verify.yaml
├── actor-env-verify.yaml
├── source-parity.yaml
├── metric-policy.yaml
├── launch-preflight.yaml
├── baseline-mode-verify.yaml or optimized-mode-verify.yaml
└── launch-allow.yaml
```

`launch-allow.yaml` is the only valid launch permit and must include:

```yaml
training_launch_allowed: true
ray_cleanup_passed: true
topology_verified: true
actor_network_env_verified: true
source_parity_verified: true
metric_policy_verified: true
launch_preflight_verified: true
phase_mode_verified: true
training_started_after_preflight: true
training_launch_method: gate_wrapper
training_script_directly_invoked: false
```

If any gate fails, the wrapper must not launch training. It must write `launch-allow.yaml` with `training_launch_allowed: false`, return a non-zero exit code, and the runner must return `status=blocked` with artifact paths. The failure then follows the normal failure branch: runner → workflow-supervisor → debug-isolator → workflow-supervisor → context-curator → retry original phase.

Base environment readiness failures discovered during runner preflight route to `verl-npu-env-builder`, not to runner-side ad-hoc repair. The runner may clean launch-time state such as stale Ray/VERL/training processes and may start/restart Ray for the approved topology, but it must not repair CANN/Python/torch_npu/VERL installation, env-load contracts, mount setup, model/data availability, or multi-node base environment consistency. If those fail, return `status=blocked`, `training_started=false`, and `next_action=route verl-npu-env-builder`.

Background task state is not an authoritative training verdict. `background_task_status=cancelled` only means the monitor was cancelled. Runner conclusions must be derived from wrapper exit code, `exit_status.yaml`, `status.yaml`, training log boundary, and `metrics-summary.yaml`. If these disagree, the runner must use `run-evidence-analyst` or return blocked; it must not infer success or failure from the background task state alone.

## Periodic runner log polling

Runner progress must not disappear inside the private subagent context. `baseline-runner` and `optimized-runner` must actively poll the durable training logs while a baseline or optimized run is active. The polling cadence is **at least once every 5 minutes** unless the training finishes sooner. This is a phase contract, not a best-effort note.

For every baseline or optimized run, the runner must create and maintain these bounded polling artifacts:

```text
<phase>/<topology>/polling/
├── poll-status.yaml
├── poll-history.jsonl
├── latest-tail.txt
└── log-index.md
```

`poll-status.yaml` must be small, safe to read by the main controller, and updated at preflight, launch, each polling interval, and finalization. It must include:

```yaml
run_id: <run-id>
phase: baseline|optimized
topology: <topology>
state: pending|preflight|launching|running|success|failed|blocked|unknown
last_update: <ISO timestamp>
poll_interval_seconds: 300
last_poll_time: <ISO timestamp or null>
next_poll_due: <ISO timestamp or null>
wrapper_pid: <pid or null>
training_pid: <pid or null>
background_task_id: <bg id or null>
training_log: <path>
orchestrator_log: <path>
pid_file: <path>
exit_status: <path>
metrics_summary: <path>
current_step: <int or null>
total_steps: <int or null>
last_metric_step: <int or null>
latest_tail: <path>
poll_history: <path>
failure_boundary: <short string or null>
next_status_command: <safe bounded command or null>
```

Each line in `poll-history.jsonl` must be one small JSON object containing at least `poll_time`, `state`, `current_step`, `total_steps`, `last_metric_step`, `training_pid_alive`, and `summary`. `latest-tail.txt` must contain only a bounded recent tail or summary, not the full training log. `log-index.md` must list durable log paths, PID/status artifacts, preflight artifacts, polling artifacts, and the safe bounded command a user can run to inspect current progress.

When the user asks for current progress, the controller may read `polling/poll-status.yaml`, `polling/log-index.md`, and the latest bounded `poll-history.jsonl` entries directly because they are bounded status artifacts. The controller must still dispatch `run-evidence-analyst` for bulky logs, dense tracebacks, profiler data, or root-cause extraction.

If the runner cannot poll logs on schedule because the wrapper, monitor, filesystem, or log path failed, it must set `state: unknown` or `state: blocked`, record the reason in `failure_boundary`, append a bounded poll-history record, and return a blocked result rather than forcing the user to infer state from private subagent messages.

## Controller loop

For each phase:

1. Determine whether the phase gate is satisfied.
   - First perform the controller self-check: "Am I about to do phase-worker analysis, training, implementation, comparison, debug, or reporting myself?" If yes, stop and dispatch the matching subagent instead.
2. Update `phase-state.yaml` for the current phase before dispatch:
    - `expected_agent`: the phase agent the controller intends to dispatch.
    - `allowed_agents`: the set of role names that are valid for this phase.
    - `fallback_to_default_agent_detected`: `false` before dispatch, then updated after dispatch.
    - `routing_blocker`: `none` before dispatch, then updated to a blocker if identity checks fail.
    - Required artifact paths for this phase.
    - `controller_non_substitution`: state confirming the controller is not doing phase-agent work directly.
3. Write the phase `work-order.md` with:
   - objective
   - required inputs
   - allowed actions
   - forbidden actions
   - expected artifacts
   - stop conditions
4. Create `runs/{run-id}/delegations/{phase}-{timestamp}.md` before dispatching the subagent. Include the canonical background-dispatch fields: `dispatch_mode: background`, `run_in_background: true`, `background_task_id: null`, `child_session_id: null`, `background_output_retrieved: false`.
5. Dispatch exactly one phase subagent with `task(..., run_in_background=true)` unless `optimization-analyst` needs bounded independent file-mapping fan-out. Each fan-out still needs its own delegation record and must also use `run_in_background=true`.
   - Record the returned `background_task_id` and `child_session_id` (when known) in the delegation record and `phase-state.yaml`.
   - Do not call `background_output` immediately. Wait for the runtime's background completion notification.
6. After receiving the completion notification, call `background_output` with the recorded `background_task_id` to retrieve the full result, and set `background_output_retrieved: true` in the delegation record and `phase-state.yaml`.
7. Require the subagent to return artifact paths, `change-ledger.md`, checkpoint status, and `delegation-result.yaml`.
8. After retrieving the background output, read `delegation-result.yaml` and update `phase-state.yaml` with:
    - `actual_agent`: the agent that produced the phase result.
    - `fallback_to_default_agent_detected`: `true` if the returned session or result came from the default/main agent or any unexpected role.
    - `routing_blocker`: `none` only if the actual agent is allowed and matches the current phase, any required gate-wrapper preflight artifacts are valid, direct training launch did not occur, any required periodic log polling artifacts exist, and any required archive gate is complete; otherwise use `main_agent_substitution`, `non_workflow_agent`, `phase_agent_required`, `archive_gate_required`, `preflight_gate_required`, `direct_training_launch`, `log_polling_required`, or `synchronous_subagent_dispatch` if background dispatch was violated.
9. Update the delegation record with status, session/task identifiers when available, output artifact paths, and blocker/failure summary when applicable.
10. Dispatch `workflow-supervisor` with `task(..., run_in_background=true)`, the phase output, artifact paths, and delegation record path. Record its `background_task_id` and `child_session_id` (when known). Wait for the background completion notification, then call `background_output` to retrieve the supervisor verdict before using it.
11. Persist the verdict under `runs/{run-id}/supervisor-verdicts/{phase}-{timestamp}.yaml`.
12. Update `runs/{run-id}/sessions.md` with the current phase, session map, latest delegation, latest supervisor verdict, and next controller action.
13. Advance only if `transition_allowed: true` and required artifacts exist.

`workflow-supervisor` must reject or block the phase with reason `phase_agent_required` when any of the following is true:

- `actual_agent` is not in `allowed_agents`.
- `fallback_to_default_agent_detected` is `true`.
- `routing_blocker` is not `none`.
- `delegation-result.yaml` or other required structured result artifacts are missing.

`workflow-supervisor` must reject or block the phase with reason `archive_gate_required` when the phase result contains a verified root cause and verified fix but lacks `archive_gate.archive_review_done: true` and an `archive_decision`.

`workflow-supervisor` must reject or block `baseline-runner` and `optimized-runner` results with reason `preflight_gate_required` or `direct_training_launch` when any of the following is true:

- The result does not prove that training was launched through `<workspace>/scripts/run_training_with_gates.sh` or an explicitly equivalent workspace-local gate wrapper.
- `training_launch_method` is not `gate_wrapper`.
- `training_script_directly_invoked` is `true` or omitted.
- Any required preflight artifact is missing: `ray-cleanup.yaml`, `topology-verify.yaml`, `actor-env-verify.yaml`, `source-parity.yaml`, `metric-policy.yaml`, or `launch-allow.yaml`.
- Any required launch-time preflight artifact is missing: `launch-preflight.yaml` plus `baseline-mode-verify.yaml` for baseline or `optimized-mode-verify.yaml` for optimized.
- `launch-allow.yaml` is missing any required boolean field, or any required boolean is not `true` for a training run that actually launched.
- The gate artifacts show `training_started_after_preflight` is not `true`.
- The gate artifacts show `launch_preflight_verified` or `phase_mode_verified` is not `true` for a launched run.
- A runner preflight failure occurred but training still launched.
- The runner claims success from background task status alone rather than wrapper/status/log/metrics artifacts.

`workflow-supervisor` must reject or block `baseline-runner` and `optimized-runner` results with reason `log_polling_required` when any of the following is true:

- `polling/poll-status.yaml` is missing.
- `polling/poll-history.jsonl` is missing for a launched run.
- `polling/log-index.md` is missing.
- `poll-status.yaml` omits any required field needed for progress inspection: `poll_interval_seconds`, `last_poll_time`, `next_poll_due`, `training_log`, `orchestrator_log`, `pid_file`, `exit_status`, `metrics_summary`, `latest_tail`, or `poll_history`.
- `poll_interval_seconds` is greater than `300` for an active training run.
- A running training process has a polling gap greater than 5 minutes plus a small scheduling tolerance, unless the runner records a bounded reason and returns `status=blocked` or `state=unknown`.
- The result includes only private subagent log summaries and does not expose polling artifacts under the run directory.
- `latest-tail.txt` is missing for a launched run, unless the runner returned `status=blocked` before any training process started.

When the controller needs facts from large logs or bulky intermediate evidence, insert an auxiliary `run-evidence-analyst` dispatch before deciding. The controller should pass a narrow question and evidence paths, then consume only the bounded summary artifact.

## Optional event log

The controller may append a short event to `workflow-events.yaml` after each significant state change, such as dispatch, supervisor verdict, phase advance, or block. This is optional and additive; it does not replace `sessions.md`, `delegations/`, or `supervisor-verdicts/`.

## Evidence analysis branch

`run-evidence-analyst` is an explicit branch of the workflow. It is used whenever a phase decision depends on bulky evidence:

```text
phase needs log/result/profiler/intermediate evidence
→ run-evidence-analyst
→ context-curator
→ return bounded summary to the current phase
```

Use this branch before or during `baseline-runner`, `optimized-runner`, `benchmark-comparator`, `debug-isolator`, or `experiment-reporter` whenever the controller would otherwise need to read large logs or dense intermediate outputs itself.

Rules:

- The branch does not advance the phase state by itself.
- The branch does not replace `workflow-supervisor`; the original phase still needs supervisor approval before transition.
- The branch output must be an artifact path plus bounded summary.
- The main controller must not paste raw log chunks, full tracebacks, profiler dumps, or dense intermediate outputs into its own context.

## Default phase order

```text
optimization-analyst
→ workflow-supervisor
→ context-curator
→ verl-npu-env-builder
→ workflow-supervisor
→ baseline-runner
→ workflow-supervisor
→ optimization-implementer
→ workflow-supervisor
→ optimized-runner
→ workflow-supervisor
→ benchmark-comparator
→ workflow-supervisor
→ experiment-reporter
```

## Topology pair progression

For multi-topology VERL/NPU experiments, treat each topology as one comparison unit. The default progression is:

```text
single-node pair → dual-node pair → four-node pair
```

Each topology pair must complete this full sequence before the next topology can start:

```text
baseline-runner(topology=N)
→ workflow-supervisor
→ optimization-implementer when implementation for this topology is not already approved and active
→ workflow-supervisor when implementation ran
→ optimized-runner(topology=N)
→ workflow-supervisor
→ benchmark-comparator(topology=N, baseline=N, optimized=N)
→ workflow-supervisor
```

Rules:

- Always run the baseline for a topology before the optimized run for the same topology.
- Always compare the baseline and optimized results for the same topology before starting any larger topology.
- Do not start dual-node testing until the single-node baseline+optimized comparison has a persisted comparator checkpoint and supervisor approval.
- Do not start four-node testing until the dual-node baseline+optimized comparison has a persisted comparator checkpoint and supervisor approval.
- A baseline or optimized result from one topology cannot satisfy another topology's gate.
- If the user explicitly requests skipping a topology, record that user decision in `sessions.md`, the relevant work-order, and the comparison/report artifacts. Without explicit user approval, skipping single-node or dual-node is a `topology_order_violation`.
- If a topology pair is `incomparable`, `invalid_run`, `blocked`, or `failed`, do not continue to the next topology. Route to the appropriate retry/debug path first.

For each topology pair, store artifacts under a topology-qualified path or include a topology field in every phase artifact, for example:

```text
runs/{run-id}/baseline/{topology}/...
runs/{run-id}/optimized/{topology}/...
runs/{run-id}/comparison/{topology}/...
```

`sessions.md` must show the current topology, completed topology pairs, latest pair verdict, and the next allowed topology action.

## Failure branch

From any failed or rejected phase:

```text
failed phase
→ debug-isolator
→ workflow-supervisor
→ context-curator
→ archive gate if root cause and fix are verified
→ retry original failed phase
```

The controller must not skip to the next phase after debug. Debug only repairs or explains the failed phase; the original phase agent must be re-dispatched. Treat a debug result as insufficient unless `root-cause.md` contains an evidence-backed RCA with failure boundary, root cause location, hypotheses, evidence chain, 5-Why chain, eliminated causes, conclusion, confidence, and missing evidence. If debug cannot identify the root cause, it must block or fail with the missing evidence instead of returning a shallow fix.

If `debug-isolator` or any retry-phase agent verifies both the root cause and the fix, it must complete the Verified RCA archive gate before the original phase is retried or the workflow advances.

When writing `runs/{run-id}/debug/work-order.md`, inject this requirement verbatim:

```text
root-cause.md MUST contain: Failure Boundary, Root Cause Location, Hypotheses Considered, Evidence Chain, 5-Why Chain, Eliminated Causes, Root Cause Conclusion, Confidence, Missing Evidence. Evaluate at least three plausible hypotheses unless the evidence proves fewer are possible. If root cause is not supported, return blocked/failed and list the missing evidence; do not mark fixed.
```

`workflow-supervisor` must reject a debug result if this RCA structure is missing or if `status=fixed` does not have a direct evidence chain from failure boundary to fix.

## Controller non-substitution gate

Before any phase transition, verify:

```yaml
controller_non_substitution:
  phase_work_done_by_main_agent: false
  phase_agent_dispatched: true
  delegation_record_created_before_dispatch: true
  returned_agent_matches_expected_role: true
  fallback_to_default_agent_detected: false
background_dispatch:
  run_in_background: true
  background_task_id_recorded: true
  background_output_retrieved: true
  supervisor_background_output_retrieved: true
archive_gate:
  required_when_verified_root_cause_and_fix: true
  archive_review_done_before_continue: true
training_launch_gate:
  required_for_baseline_and_optimized_runner: true
  gate_wrapper_used: true
  direct_training_launch_detected: false
  launch_allow_yaml_valid: true
  log_polling_gate:
  required_for_baseline_and_optimized_runner: true
  poll_status_yaml_present: true
  poll_history_present: true
  log_index_present: true
  max_poll_interval_seconds: 300
  runner_preflight_gate:
    required_for_baseline_and_optimized_runner: true
    launch_preflight_verified: true
    phase_mode_verified: true
    training_started_when_preflight_failed: false
  topology_pair_gate:
    current_topology_baseline_before_optimized: true
    current_topology_compared_before_next_topology: true
    topology_order: single_node_then_dual_node_then_four_node
```

If any value fails, the workflow must enter `blocked` and ask for repair or explicit mode switch. The main controller may summarize why it blocked, but it must not complete the phase itself.

## Phase gates

- `verl-npu-env-builder` requires model path, dataset path, training script path, container/image assumptions, and mount policy.
- `baseline-runner` requires an approved environment checkpoint, must confirm it is running the unoptimized baseline, owns periodic baseline log polling as a required role capability, must update polling artifacts at least once every 5 minutes while training is active, and must launch only through the workspace gate wrapper. The wrapper must complete/document Ray cleanup, topology verification, actor network env verification, source parity verification, metric policy verification, launch-time preflight, and baseline-mode verification before any real baseline training launch. If preflight fails, baseline training must not start. Direct baseline script execution is invalid evidence.
- `optimization-implementer` requires a successful baseline checkpoint.
- `optimized-runner` requires an implementation checkpoint, owns periodic optimized log polling as a required role capability, must update polling artifacts at least once every 5 minutes while training is active, and must launch only through the workspace gate wrapper. The wrapper must complete/document Ray cleanup, topology verification, actor network env verification, source parity verification, metric policy verification, launch-time preflight, and optimized-mode verification before any real optimized training launch. If preflight fails, optimized training must not start. Direct optimized script execution is invalid evidence.
- `benchmark-comparator` requires baseline and optimized metric summaries with compatible units, windows, seeds/configs, and quality constraints.
- Topology progression requires each topology's baseline+optimized comparison checkpoint and supervisor approval before the next topology starts; default order is single-node, then dual-node, then four-node unless the user explicitly approves a skip.
- `experiment-reporter` requires either an approved comparison checkpoint or a blocked-state report.

## Required user-specified inputs

This is a generic VERL multi-agent workflow skill. It must not embed one experiment's container name, model path, dataset name, training script, NPU card list, or output directory as defaults.

Before the environment phase can run, obtain these inputs from the user. If the assistant discovers candidates from files, logs, configs, shell output, or prior project memory, treat them only as **unconfirmed candidates**. Present the candidates to the user and wait for explicit confirmation before using them.

| Input | Why it is required | If missing or only discovered |
|---|---|---|
| Project root | Determines where workflow contracts and agent definitions live | Ask the user to specify or confirm the discovered root |
| Workflow workspace | Owns `runs/{run-id}/`, scripts, temp files, generated configs, evidence, and archive outputs | Block all execution phases until the user specifies or confirms it |
| Run objective | Defines whether this is baseline, optimization, comparison, debug, or report work | Ask the user to specify the objective |
| Existing container name or container image/runtime plan | Determines where VERL/NPU commands can safely run | If the user specifies an existing container, image may be omitted; otherwise block until the user specifies the image/runtime plan |
| Model path or model identifier | Required by training/inference scripts | Block environment phase until user specifies or confirms it |
| Train dataset path | Required for baseline/optimized training | Block environment phase until user specifies or confirms it |
| Eval/test dataset path, if the workflow compares quality | Required for comparable metrics | Block environment phase unless the user explicitly confirms none is needed |
| Training script path or command template | Required to know the actual VERL entrypoint | Block environment phase until user specifies or confirms it |
| VERL repository/root path | Required to validate scripts and dependencies | Block environment phase until user specifies or confirms it |
| NPU device selection | Required for safe NPU scheduling | Block execution phases until user specifies or confirms it |
| Baseline/optimized comparison metrics | Required before `benchmark-comparator` can issue a verdict | Block comparison phase until user specifies or confirms them |

If a critical input is missing or merely discovered, do not invent or silently accept it from prior runs. Ask the user to specify or confirm it. If multiple required inputs are absent, report a blocked state with a concise checklist of missing confirmations.

### Interactive startup intake

Start with an intake pass before executing the workflow:

1. Parse the user's message for all required inputs.
2. Mark each input as one of:
   - `confirmed`: explicitly provided or explicitly confirmed by the user.
   - `candidate`: discovered by the assistant but not yet confirmed by the user.
   - `missing`: not provided and not discovered.
3. If every required input is `confirmed`, do not ask more intake questions. Proceed to create the workspace state and begin the controller loop.
4. If any required input is `candidate`, show the candidate values and ask the user to confirm or replace them.
5. If any required input is `missing`, ask only for the missing fields. Group related fields in one concise question instead of asking one message per field.
6. Do not enter environment, baseline, optimized, comparison, debug execution, or report generation until all execution-relevant fields are `confirmed`.

Use this intake checklist:

```text
请补充或确认以下启动信息：
1. 项目根目录：
2. 工作区：
3. 本次目标：
4. 执行环境：已有容器名，或待创建镜像 + runtime plan：
5. 模型路径或模型 ID：
6. train 数据集路径：
7. eval/test 数据集路径，或确认本次不需要：
8. 训练脚本路径或命令模板：
9. VERL_ROOT：
10. NPU 设备选择：
11. baseline/optimized 对比指标：
```

If the user already provided a complete checklist in one message, acknowledge the confirmed fields briefly and continue without interactive questioning.

### Workspace ownership rule

The workflow workspace is a user-controlled prerequisite. Without a user-specified or user-confirmed workspace, do not start environment checks, training, debug scripts, conversion scripts, benchmark runs, or report generation.

Once the user specifies the workspace, place all workflow-generated material inside it:

```text
<workspace>/
├── runs/{run-id}/                 # Work orders, ledgers, checkpoints, metrics, reports
├── scripts/                       # Generated helper scripts and rerun wrappers
├── tmp/                           # Temporary files created by the workflow
├── evidence/                      # Bounded copied evidence and summaries
├── archive/                       # Final packaged run artifacts or manifests
├── indexes/                       # Lightweight searchable summaries of runs and incidents
└── worktrees/                     # Optional isolated implementation worktrees
```

Do not write workflow helper scripts, temporary files, generated configs, copied logs, or archive outputs outside the confirmed workspace. External inputs such as model weights, datasets, and source repositories may remain at their user-confirmed locations; the workspace stores workflow outputs and generated artifacts.

### Session ledger structure

Borrow the continuity-ledger idea from micode, but keep this workflow's phase gates. `runs/{run-id}/sessions.md` is the controller's resume ledger and must stay concise.

Use this structure:

```markdown
# Session: {run-id}
Updated: {ISO timestamp}

## Goal
{One sentence success criterion}

## Confirmed Inputs
- Project root:
- Workspace:
- Container or image:
- Model:
- Train dataset:
- Eval/test dataset:
- Training script:
- VERL_ROOT:
- NPU devices:
- Metrics:

## Current Phase
- State: pending | ready | running | supervision | passed | failed | blocked
- Active phase:
- Current topology: single-node | dual-node | four-node | custom | none
- Next controller action:

## Topology Pair Progress
| Topology | Baseline | Optimized | Comparison verdict | Supervisor verdict | Next allowed action |
|---|---|---|---|---|---|
| single-node | pending | pending | pending | pending | run single-node baseline |
| dual-node | blocked_until_single_done | pending | pending | pending | blocked |
| four-node | blocked_until_dual_done | pending | pending | pending | blocked |

## Progress
### Done
- [x] {completed phase or gate}

### In Progress
- [ ] {current controller task}

### Blocked
- {missing user confirmation, failed gate, or unsafe action}

## Key Decisions
- {decision}: {rationale}

## Delegation Map
| Phase | Agent | Session/task id | Delegation record | Supervisor verdict |
|---|---|---|---|---|

## File Operations
### Read
- `{paths read}`

### Modified
- `{paths edited}`

### Generated
- `{scripts, configs, summaries, checkpoints generated under workspace}`

## Critical Context
- {short facts needed after compaction}

## Next Steps
1. {ordered next controller action}
```

Do not put raw logs, full tracebacks, full diffs, dense profiling output, credentials, or private keys into `sessions.md`.

### File operation tracking

Every `change-ledger.md` should include a small file-operation section:

```markdown
## File Operations
### Read
- `{path}`: {why it was read}

### Modified
- `{path}`: {what changed and why}

### Generated
- `{workspace-relative path}`: {what it contains}

### External Inputs Referenced
- `{path}`: {model, dataset, source repo, or container path; no copy unless needed}
```

This is for deterministic recovery and review. Keep it path-oriented and concise.

### Archive and search conventions

At milestones, write small searchable summaries under the confirmed workspace:

```text
<workspace>/indexes/runs/{run-id}.md
<workspace>/indexes/incidents/{run-id}-{phase}.md
<workspace>/archive/{run-id}/manifest.md
```

Use these summaries for future recall of prior baseline runs, debug incidents, comparison decisions, and reusable container/data/script findings. Do not copy dense logs into indexes. Store only titles, tags, confirmed inputs, phase verdicts, root-cause summaries, metric summaries, and artifact paths.

### Workspace worktree isolation

For `optimization-implementer`, code changes may use a git worktree for isolation, but only under the confirmed workspace:

```text
<workspace>/worktrees/{run-id}-{feature}/
```

Do not create worktrees in the repository parent directory by default. Do not use worktree isolation for environment or baseline phases. Before creating a worktree, confirm the target source repository and branch with the user if not already confirmed.

### Do not import micode workflow semantics

The borrowed ideas above are only infrastructure patterns: continuity ledger, artifact summaries, file-operation tracking, and optional worktree isolation. Do not replace this workflow with micode's `Brainstorm → Plan → Implement` flow, do not auto-handoff phases without `workflow-supervisor`, and do not add micode agents to the active 10-agent set.

### Container/image rule

At workflow start, the user must specify one of these execution substrates:

1. **Existing container name**: use that container after verifying it exists and matches the required VERL/NPU environment checks. In this case the image name is not required.
2. **User-specified container image plus runtime plan**: use this when no existing container is specified and the user directly provides the image.
3. **Archived baseline image fallback**: if the user does not specify an existing container and does not specify an image, the controller may only use a baseline image archived under `/mnt/disk2t/l30002999`. Treat discovered archived images as candidates and ask the user to confirm which one to use before creating a container.

If neither an existing container nor a user-specified image is provided, do not choose an arbitrary image. Search only the archived baseline image area under `/mnt/disk2t/l30002999`, present candidates, and block before `verl-npu-env-builder` until the user confirms the image. If no archived baseline image candidate exists, block and ask the user to provide an image.

When creating a container for this workflow, use this mount/device baseline unless the user explicitly overrides it:

```bash
docker run -itd --name <container-name> \
  --privileged -u root --network host --ipc=host \
  --device=/dev/davinci_manager \
  --device=/dev/devmm_svm \
  --device=/dev/hisi_hdc \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  -v /usr/local/Ascend/driver/lib64/common:/usr/local/Ascend/driver/lib64/common \
  -v /usr/local/Ascend/driver/lib64/driver:/usr/local/Ascend/driver/lib64/driver \
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  -v /mnt/sfs_turbo:/mnt/sfs_turbo \
  -v /mnt/disk2t:/mnt/disk2t \
  <confirmed-image>
```

After creation, verify both shared mounts are visible inside the container and verify NPU visibility with `npu-smi info` or the environment-appropriate check.

Use this confirmation pattern:

```text
我发现了以下候选基础条件，但还不能使用，必须由你确认：
- 项目根目录：<candidate>
- 工作区：<candidate>
- 已有容器或待创建镜像：<candidate>
- 模型路径：<candidate>
- 数据集 train：<candidate>
- 数据集 test：<candidate or none>
- 训练脚本：<candidate>
- VERL_ROOT：<candidate>
- NPU 设备：<candidate>

请确认这些值是否作为本次 workflow 输入；未确认前我不会写入工作区，也不会进入 environment/baseline 执行阶段。
```

## Context policy

Keep the main context small and auditable:

- Pass artifact paths and bounded summaries.
- Do not paste raw logs, full tracebacks, dense profiling dumps, full diffs, install logs, credentials, tokens, or private keys.
- Store raw or dense evidence only as files under the run directory or approved external artifact paths.

## Startup prompt template

When the user asks how to start the workflow, offer this prompt:

```text
请使用 verl-subagent-union-workflow skill，按本项目 Main Agent Controller Protocol 启动 VERL/NPU multi-agent workflow。

项目根目录：<用户明确指定或确认的 sub-agent-union-work 项目根目录>
工作区：<用户明确指定或确认的 workflow workspace；所有 runs/scripts/tmp/evidence/archive 都写入这里>

本次目标：<写实验/优化/baseline目标>

已知输入：
- 已有容器或待创建镜像：
- 模型路径：
- 数据集 train：
- 数据集 test：
- 原始数据/图片目录：
- 训练脚本路径：
- VERL_ROOT：
- NPU 卡：
- baseline/optimized 对比指标：

controller 规则：
1. 你是 main agent/controller，不是 phase worker。
2. 在用户确认的工作区内创建或选择 runs/{run-id}/。
3. 每个 phase 前写 work-order.md。
4. 每次调用 subagent 前写 delegations/{phase}-{timestamp}.md。
5. subagent 返回后更新 delegation record。
6. 每个 phase 后调用 workflow-supervisor。
7. 只有 supervisor verdict 中 transition_allowed=true 且 verdict 已落盘，才能进入下一 phase。
8. 持续维护 sessions.md 用于 compaction/restart 恢复。
9. 子 agent 不得互相 handoff；所有 phase transition 必须回到 controller。
10. 任意失败走 failed phase → debug-isolator → workflow-supervisor → context-curator → retry original failed phase。
11. baseline-runner / optimized-runner 必须通过 workspace gate wrapper 启动训练，并在训练运行期间至少每 5 分钟轮询一次训练日志，持续更新 polling/poll-status.yaml、polling/poll-history.jsonl、polling/latest-tail.txt 与 polling/log-index.md，方便用户主动查询最新训练状态。
```

The user may also start with a shorter request such as “启动这个 VERL 多 agent workflow”. In that case, run the interactive startup intake above and ask for the missing fields.

## If inputs are missing

Do not guess missing high-risk inputs, and do not silently use discovered candidates. Ask the user to specify or confirm prerequisites that change execution safety or artifact location, such as project root, workflow workspace, model path, dataset path, script path, VERL root, container name/image, NPU device selection, comparison metrics, or whether to start a real training run.
