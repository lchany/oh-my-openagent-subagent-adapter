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

## Updating

After changing the plugin, update the plugin version cachebuster and reinstall:

```bash
python3 /root/.codex/skills/.system/plugin-creator/scripts/update_plugin_cachebuster.py plugins/verl-subagent-union-workflow
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Start a new thread after reinstalling so Codex reloads the plugin and bundled skill.
