# VERL subagent union workflow

This package contains an OpenCode workflow skill plus the subagents used to run a controlled VERL + Ascend/NPU optimization experiment.

It is designed for the patched `task(subagent_type="...")` path documented in this repository: custom OpenCode agents live under `.opencode/agents`, while the workflow skill lives under `.opencode/skills`.

## Layout

```text
verl-subagent-union-workflow/
├── agents/                                  # OpenCode subagent definitions
├── skills/verl-subagent-union-workflow/     # Main controller workflow skill
└── manifest.md                              # Agent inventory and workflow summary
```

## Install into an OpenCode config

Copy the package into either a project-local OpenCode config or the user config:

```bash
cp -R verl-subagent-union-workflow/agents/* <project>/.opencode/agents/
cp -R verl-subagent-union-workflow/skills/* <project>/.opencode/skills/
```

or globally:

```bash
cp -R verl-subagent-union-workflow/agents/* ~/.config/opencode/agents/
cp -R verl-subagent-union-workflow/skills/* ~/.config/opencode/skills/
```

Then verify discovery:

```bash
opencode agent list
```

## Workflow model

The main agent acts only as the controller. It writes work-orders, delegation records, phase state, session ledgers, and supervisor verdicts, but it does not perform phase work itself.

Default phase order:

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

For multi-topology experiments, each topology is a comparison pair. The default order is:

```text
single-node baseline+optimized+comparison
→ dual-node baseline+optimized+comparison
→ four-node baseline+optimized+comparison
```

The next topology cannot start until the current topology pair has a persisted comparison checkpoint and supervisor approval, unless the user explicitly records a skip decision.

## Safety rules

- All workflow subagents run in the background and require persisted artifacts before supervision.
- `baseline-runner` and `optimized-runner` must not directly invoke training scripts; they launch only through the workspace gate wrapper.
- Runner preflight failure is fail-closed: training must not start.
- `verl-npu-env-builder` owns base environment preparation and repair; runners only do launch-time checks.
- `optimization-implementer` implements only the approved core patch, then requires `review-work` plus Oracle plan-alignment review.
- Raw logs, full tracebacks, profiler dumps, full diffs, credentials, and private artifacts stay out of the main context.

See `manifest.md` for the agent inventory.
