# Local Codex VERL multi-agent workflow

This directory archives the Codex/ChatGPT workflow used locally for VERL Baseline-versus-Optimized training on Ascend NPUs. Install, run, test, patch, and version it from this directory only.

## Runtime roles

- Main thread: controller, complete intake owner, and the only user-facing role.
- `baseline_runner`: prepares, repairs, runs, and closes Baseline.
- `optimized_runner`: applies only the approved optimization, then runs and closes Optimized.
- `workflow_supervisor`: read-only terminal review after each Runner.
- `benchmark_comparator`: computes step-time, throughput, and reward deltas without judging reward reasonableness.
- `experiment_reporter`: writes the final concise report.

The two Runners execute sequentially on the same confirmed NPU allocation by default. They may make implementation decisions autonomously after intake, but may never ask the user or spawn another agent.

## Install locally

```bash
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Start a new Codex thread in a project that contains the five files under `.codex/agents/`, then invoke:

```text
$verl-subagent-union-workflow
```

See [docs/workflow.md](docs/workflow.md) and [docs/verl-rollout8-pre-run-confirmation.html](docs/verl-rollout8-pre-run-confirmation.html).

For installation in a new environment or step-by-step diagnosis of an old environment, follow [docs/codex-workflow-bootstrap-and-recovery.md](docs/codex-workflow-bootstrap-and-recovery.md) and run:

```bash
./scripts/audit_codex_workflow.sh
```

## Versioning

`versions/v1/` contains the initial Codex workflow patch; `versions/v2/` contains the bootstrap/recovery guidance and audit patch. Generated run directories, raw logs, per-step result files, checkpoints, and local agent evidence are not project source and are not archived here.

Load only the agents, skills, plugin metadata, tests, patches, and runtime state owned by this directory.
