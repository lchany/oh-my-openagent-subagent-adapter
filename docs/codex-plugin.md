# Codex plugin workflow

This repository includes a Codex CLI version of the VERL subagent union workflow. It is designed to be committed to GitHub and reused on another machine after cloning the repository.

## What is included

- `.agents/plugins/marketplace.json`: repo-local Codex marketplace.
- `plugins/verl-subagent-union-workflow/`: installable Codex plugin.
- `.codex/agents/*.toml`: repo-scoped Codex custom agents converted from the OpenCode agent definitions.
- `.codex/config.toml`: repo-scoped Codex feature configuration enabling the custom-agent capable multi-agent implementation.
- `verl-subagent-union-workflow/`: original OpenCode workflow, kept unchanged for compatibility.

## Install on another machine

Clone the repository, enable custom-agent dispatch, then start Codex from the repository root.

```bash
git clone https://github.com/lchany/oh-my-openagent-subagent-adapter.git
cd oh-my-openagent-subagent-adapter
```

Recommended persistent setup for current Codex builds:

```toml
# ~/.codex/config.toml
[features]
multi_agent_v2 = true
```

Then start Codex normally:

```bash
codex
```

If you do not want to change user config, enable the feature per launch:

```bash
codex --enable multi_agent_v2
```

In the Codex CLI, open the plugin browser:

```text
/plugins
```

Select the `oh-my-openagent local` marketplace, install `VERL Subagent Union Workflow`, then start a new thread.

If the marketplace is not visible, add the repo marketplace root explicitly:

```bash
codex plugin marketplace add .
```

Then reinstall from the marketplace:

```bash
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

## Triggering

The workflow is explicit-only. The plugin skill sets `allow_implicit_invocation: false`, so ordinary VERL/NPU prompts should not start the workflow.

Start it by explicitly invoking the plugin or skill, for example:

```text
@VERL Subagent Union Workflow Start VERL workflow controller
```

or:

```text
$verl-subagent-union-workflow
```

## Smoke test

After installing the plugin, use a harmless prompt from a new thread:

```text
@VERL Subagent Union Workflow Start the controller and route this as a small workflow-support classification. Use workflow_generalist only; do not run training or edit files.
```

Expected result:

- The controller treats itself as controller-only.
- It routes the small request to `workflow_generalist`.
- It must not substitute `default`, `explorer`, or `worker` for `workflow_generalist`.
- It returns a bounded summary and does not run training, inspect bulky logs, or edit implementation files.

For a non-interactive custom-agent check:

```bash
codex exec --cd "$PWD" \
  'Spawn the custom agent named workflow_generalist for a smoke test. Do not substitute default, explorer, or worker. The subagent must not run commands or edit files. Ask it to return only: role=workflow_generalist and specialized_agent_applicable=false.'
```

If `multi_agent_v2` is not enabled in user config, add `--enable multi_agent_v2` to the `codex exec` command.

## GitHub-backed worktree stacks

The Codex workflow supports VERL projects where GitHub branches are the source of truth, local git worktrees hold the management, baseline, and optimized source trees, and a stack wrapper switches the runtime source tree inside training containers.

This mode assumes the user has already chosen the optimization plan, identified the modules likely to change, implemented or supervised the optimized code, and placed baseline and optimized code under git worktree management. The workflow then runs the controlled experiment rather than inventing the optimization.

Expected project shape:

```text
<management-worktree>/
  stacks/verl/<project>/
    stack.json
    scripts/switch_stack.py
    scripts/trainctl.py
    inventories/*.json
    variants/<variant>/*.sh
<baseline-source-worktree>/
<optimized-source-worktree>/
```

In this mode, `verl_npu_env_builder` performs the pre-run gate for each variant: model path, dataset path, inventory, container readiness, training/Ray scripts, and runtime switching through `switch_stack.py`. Runners then launch through `trainctl.py`; they must not directly invoke `container_train_*.sh` when `trainctl.py` exists. After each successful runner phase, `source_release_manager` records and publishes, when authorized, the validated training/Ray script state and source commit state for that variant.

Default topology order:

```text
single-node baseline env+run+publish
single-node optimized env+run+publish
single-node comparison
dual-node baseline env+run+publish
dual-node optimized env+run+publish
dual-node comparison
four-node baseline env+run+publish
four-node optimized env+run+publish
four-node comparison
final report
```

Minimal work-order fields:

```yaml
source_release:
  remote: "git@github.com:lchany/hw-gitworktree-baseline-optimized.git"
  sync_policy: "push_allowed"
  publish_training_scripts_after_success: true
  publish_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
  management:
    branch: "main"
    worktree: "/mnt/disk2t/l30002999/hw-gitworktree-baseline-optimized"
  baseline:
    branch: "verl-mini-video-baseline"
    worktree: "/mnt/disk2t/l30002999/hw-gitworktree-baseline-optimized-baseline"
    immutable: true
  optimized:
    branch: "verl-mini-video-optimized-v4"
    worktree: "/mnt/disk2t/l30002999/hw-gitworktree-baseline-optimized-v4"
    publish_required_before_run: true
worktree_stack:
  enabled: true
  stack_root: "/mnt/disk2t/l30002999/hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare"
  inventory: "inventories/59_local_restore.json"
  nodes: "1"
  variants:
    baseline: "baseline"
    optimized: "optimized-v4"
  runtime_target: "/vllm-workspace/verl"
permissions:
  non_interactive: true
  ask_user_during_phase: false
  allow_environment_checks: true
  allow_runtime_switch: true
  allow_training_launch: true
  allow_debug_within_scope: true
  allow_git_commit: true
  allow_git_push: true
  git_push_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
```

Subagents run non-interactively from the permission envelope. If a permission is missing, the phase blocks before dispatch; subagents must not request mid-phase user confirmation.

Use `sync_policy: push_allowed` or `full_sync_allowed` when validated training/Ray scripts or explicitly approved source changes should be synchronized to GitHub after successful runs. With `permissions.allow_git_push: true`, `source_release_manager` performs the scoped push without another user prompt. Publication artifacts are variant-specific:

```text
runs/{run-id}/source/baseline/source-checkpoint.yaml
runs/{run-id}/source/optimized/source-checkpoint.yaml
```

Only training scripts, Ray startup scripts, and explicitly approved source changes are eligible for GitHub commit/push. Intermediate workflow results such as `runs/`, logs, metrics summaries, checkpoints, debug evidence, generated reports, local memory files, datasets, and model files stay local.

## Updating

After changing the plugin, update the plugin version cachebuster and reinstall:

```bash
python3 /root/.codex/skills/.system/plugin-creator/scripts/update_plugin_cachebuster.py plugins/verl-subagent-union-workflow
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Start a new thread after reinstalling so Codex reloads the plugin and bundled skill.
