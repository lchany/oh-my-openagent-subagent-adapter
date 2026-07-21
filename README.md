# Local Codex VERL multi-agent workflow

This repository archives the Codex workflow that is used locally for VERL Baseline-versus-Optimized training on Ascend NPUs. The workflow definition is rebuilt from the active local Codex process and current user rules; legacy OpenCode workflow assets are not part of this version.

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

## Versioning

`versions/v1/` contains the version manifest and patch series. Generated run directories, raw logs, per-step result files, checkpoints, and local agent evidence are not project source and are not archived here.
