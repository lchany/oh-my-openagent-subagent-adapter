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

In this mode, the workflow uses `source_release_manager` before runner phases. It verifies branch names, commits, worktree cleanliness, GitHub publication state when required, baseline absence markers, optimized presence markers, and the approved runtime switch/train wrapper contract. Runners then consume that source checkpoint and must launch through `trainctl.py`; they must not directly invoke `container_train_*.sh` when `trainctl.py` exists.

Minimal work-order fields:

```yaml
source_release:
  remote: "git@github.com:lchany/hw-gitworktree-baseline-optimized.git"
  sync_policy: "verify_only"
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
```

Use `sync_policy: verify_only` unless the current user instruction explicitly allows pull, fetch, or push. If publication must be performed, use `push_allowed` only for that phase and record the authorization in the work-order.

## Updating

After changing the plugin, update the plugin version cachebuster and reinstall:

```bash
python3 /root/.codex/skills/.system/plugin-creator/scripts/update_plugin_cachebuster.py plugins/verl-subagent-union-workflow
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Start a new thread after reinstalling so Codex reloads the plugin and bundled skill.
