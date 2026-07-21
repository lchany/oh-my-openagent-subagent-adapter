# VERL subagent union workflow manifest

## Skill

- `skills/verl-subagent-union-workflow/SKILL.md`
  - Main controller protocol for VERL + Ascend/NPU multi-subagent optimization runs.
  - Owns run state, work-orders, delegation lifecycle, topology pair progression, supervisor gates, and failure routing.

## Agents

| Agent | Role |
|---|---|
| `optimization-analyst` | Intake optimization ideas, analyze hypothesis/risk, and produce bounded code/file maps. |
| `workflow-supervisor` | Audit each phase result before the controller advances. Blocks missing artifacts, routing errors, preflight failures, topology-order violations, and scope drift. |
| `context-curator` | Keep handoffs and session ledgers bounded, path-based, and recoverable after compaction. |
| `verl-npu-env-builder` | Prepare, validate, and repair the base VERL/NPU environment. Owns env-load, CANN/torch_npu/VERL checks, mounts, and multi-node consistency. |
| `baseline-runner` | Run or validate unoptimized baseline for one topology. Performs launch-time preflight and emits only three short user-visible states: preflight, launch/running, blocked/failed. |
| `optimization-implementer` | Convert an approved optimization plan into the smallest necessary core implementation patch after a successful baseline. Requires review-work and Oracle alignment before success. |
| `optimized-runner` | Run or validate optimized training for one topology. Performs launch-time preflight and verifies optimized code/config activation. |
| `benchmark-comparator` | Compare same-topology baseline and optimized artifacts and issue the only allowed verdicts: improved, no_change, regressed, incomparable, invalid_run. |
| `run-evidence-analyst` | Inspect large logs, training outputs, profiler snippets, and bulky evidence in isolation; returns bounded summaries and evidence paths. |
| `workflow-generalist` | Handle small workflow-support tasks only when no specialized workflow agent applies. |
| `debug-isolator` | Isolate failed phase root causes with evidence-backed RCA and route retry to the original phase agent. |
| `experiment-reporter` | Build the final user-facing report and archive manifest from approved comparison or blocked-state evidence. |

## Core workflow contracts

### Controller boundary

The main agent is controller-only. It must not do phase work such as environment validation, training, implementation, comparison, bulky evidence reading, RCA/debug, or final report generation.

### Delegation lifecycle

Every workflow subagent dispatch has a stable `delegation_id` and follows:

```text
registered → running → complete | error | timeout | cancelled
```

Terminal status is immutable. A phase is not reviewable until the required structured artifacts are persisted.

### Environment and runner split

- `verl-npu-env-builder`: prepares and repairs base environment readiness.
- `baseline-runner` / `optimized-runner`: perform launch-time checks and start training only if preflight passes.

Runner state lines are intentionally short:

```text
preflight: 正在做训练前检查，训练未启动。
launch/running: 检查通过，训练已启动/正在运行。
blocked/failed: 检查失败或训练失败，说明卡在哪，训练是否启动。
```

### Topology pair progression

Default progression:

```text
single-node pair → dual-node pair → four-node pair
```

Each pair requires same-topology baseline, optimized run, benchmark comparison, and supervisor approval before the next pair starts.
