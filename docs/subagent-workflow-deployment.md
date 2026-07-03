# Subagent Workflow Deployment For New High-Performance Model Projects

This document explains how to deploy the packaged subagent workflow for another high-performance or large-model training project. It is written for projects that want to reuse the Codex subagents in this repository together with the git-worktree stack template from `hw-gitworktree-baseline-optimized` to run a controlled baseline-vs-optimized VERL/NPU experiment.

The workflow assumes the optimization design and code ownership are prepared by the project owner first. The subagents then validate the environment, switch between baseline and optimized worktrees, run training, publish approved scripts/source changes, compare results, and produce a report.

## 1. What Gets Deployed

The deployment uses two GitHub repositories:

| Repository | Purpose |
| --- | --- |
| `https://github.com/lchany/oh-my-openagent-subagent-adapter` | Installs the Codex plugin and custom subagents. This is the workflow engine. |
| `https://github.com/lchany/hw-gitworktree-baseline-optimized` | Provides the git-worktree stack pattern, runtime switch scripts, train wrapper, inventories, and baseline/optimized training script layout. This is the model-project orchestration template. |

The Codex adapter deployment has three layers:

- Repo-scoped custom agents: `.codex/agents/*.toml`
- Installable Codex plugin: `plugins/verl-subagent-union-workflow/`
- Repo-local marketplace: `.agents/plugins/marketplace.json`

The important subagents are:

| Subagent | Responsibility |
| --- | --- |
| `verl_npu_env_builder` | Check model/data/container/NPU/CANN/Ray/script readiness and switch the runtime to the requested variant. |
| `baseline_runner` | Run only the baseline phase through the approved training wrapper after preflight passes. |
| `optimized_runner` | Run only the optimized phase through the approved training wrapper after preflight passes. |
| `source_release_manager` | Commit/push only approved training scripts, Ray scripts, and explicitly approved source changes after a successful run. |
| `workflow_supervisor` | Audit every phase result and block unsafe transitions. |
| `debug_isolator` | Diagnose failed phases and route retry back to the failed phase. |
| `benchmark_comparator` | Compare same-topology baseline and optimized results. |
| `experiment_reporter` | Produce the final artifact-backed report. |

Subagents are non-interactive during a phase. Missing permissions, missing paths, or unsafe scope must return `blocked`; the subagent must not request mid-phase user confirmation.

## 2. Fast Deploy On A New Codex Machine

Use this section when you are on a fresh machine and want Codex to quickly pick up the full subagent workflow and the model stack template.

### 2.0 LLM Auto-Deployment Prompt

Give this block to an LLM/Codex agent on a new machine when you want it to deploy everything automatically:

```text
You are deploying the VERL/NPU subagent workflow on this machine.

Goal:
- Clone https://github.com/lchany/oh-my-openagent-subagent-adapter.
- Clone https://github.com/lchany/hw-gitworktree-baseline-optimized.
- Create the baseline and optimized git worktrees required by the stack template.
- Enable Codex custom-agent dispatch.
- Register the adapter repository marketplace.
- Install the verl-subagent-union-workflow plugin.
- Install the Codex custom agents into the target management repository.
- Generate a reference work-order for the mini_video_v4_compare stack.
- Verify the custom subagent route with workflow_generalist.
- Verify the model stack template from hw-gitworktree-baseline-optimized exists.
- Report the exact installed plugin version, repository paths, and whether the workflow is ready to use.

Rules:
- Do not modify model source code.
- Do not run training.
- Do not push unless explicitly instructed after deployment.
- If a command fails, stop, summarize the failing command and error, then fix only the deployment issue.
- Keep logs concise; do not paste full command output.

Commands to run:
1. Choose an install root, defaulting to /home/$USER.
2. Clone or update both repositories:
   - /home/$USER/oh-my-openagent-subagent-adapter
   - /home/$USER/hw-gitworktree-baseline-optimized
3. Create or update sibling worktrees:
   - /home/$USER/hw-gitworktree-baseline-optimized-baseline from origin/verl-mini-video-baseline
   - /home/$USER/hw-gitworktree-baseline-optimized-v4 from origin/verl-mini-video-optimized-v4
4. Ensure ~/.codex/config.toml contains:
   [features]
   multi_agent_v2 = true
5. From /home/$USER/oh-my-openagent-subagent-adapter, run:
   codex plugin marketplace add .
   codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
6. Copy /home/$USER/oh-my-openagent-subagent-adapter/.codex/agents into:
   /home/$USER/hw-gitworktree-baseline-optimized/.codex/agents
7. Create:
   /home/$USER/hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/work-orders/single-node-reference.yaml
8. Run:
   codex plugin list
9. Verify these files exist:
   - .codex/agents/workflow_generalist.toml
   - plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json
   - plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/SKILL.md
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/stack.json
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/scripts/switch_stack.py
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/scripts/trainctl.py
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/variants/baseline/container_train_1node.sh
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/variants/optimized-v4/container_train_1node.sh
   - ../hw-gitworktree-baseline-optimized/.codex/agents/workflow_generalist.toml
   - ../hw-gitworktree-baseline-optimized/stacks/verl/mini_video_v4_compare/work-orders/single-node-reference.yaml
   - ../hw-gitworktree-baseline-optimized-baseline
   - ../hw-gitworktree-baseline-optimized-v4
10. Run the non-interactive smoke test from the target management repository:
   codex exec --cd /home/$USER/hw-gitworktree-baseline-optimized 'Spawn the custom agent named workflow_generalist for a smoke test. Do not substitute default, explorer, or worker. The subagent must not run commands or edit files. Require it to return only: role=workflow_generalist and specialized_agent_applicable=false.'

Success criteria:
- The plugin list includes verl-subagent-union-workflow.
- The target management repository contains .codex/agents/*.toml.
- The smoke test result proves workflow_generalist was spawned from the target management repository.
- The baseline and optimized sibling worktrees exist.
- The stack template files under hw-gitworktree-baseline-optimized exist.
- The reference work-order exists.
- Final answer includes:
  - adapter repository path
  - stack template repository path
  - baseline worktree path
  - optimized worktree path
  - reference work-order path
  - installed plugin version
  - smoke test verdict
  - command to start using the workflow:
    cd /home/$USER/hw-gitworktree-baseline-optimized && codex
    then invoke: $verl-subagent-union-workflow
```

### 2.1 Clone Both Repositories

```bash
cd /home/$USER
git clone https://github.com/lchany/oh-my-openagent-subagent-adapter.git
git clone https://github.com/lchany/hw-gitworktree-baseline-optimized.git
cd oh-my-openagent-subagent-adapter
```

If the repositories already exist, update them before installing:

```bash
cd /home/$USER/oh-my-openagent-subagent-adapter
git pull
cd /home/$USER/hw-gitworktree-baseline-optimized
git pull
```

The adapter repository installs the workflow. The `hw-gitworktree-baseline-optimized` repository is the reference implementation for how a target model project should expose baseline/optimized source branches, stack metadata, training scripts, Ray scripts, and runtime switching.

For an LLM executor, this idempotent shell block is the preferred deployment path:

```bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/home/$USER}"
ADAPTER_REPO="$INSTALL_ROOT/oh-my-openagent-subagent-adapter"
STACK_REPO="$INSTALL_ROOT/hw-gitworktree-baseline-optimized"

mkdir -p "$INSTALL_ROOT"
cd "$INSTALL_ROOT"

if [ -d "$ADAPTER_REPO/.git" ]; then
  git -C "$ADAPTER_REPO" pull
else
  git clone https://github.com/lchany/oh-my-openagent-subagent-adapter.git "$ADAPTER_REPO"
fi

if [ -d "$STACK_REPO/.git" ]; then
  git -C "$STACK_REPO" pull
else
  git clone https://github.com/lchany/hw-gitworktree-baseline-optimized.git "$STACK_REPO"
fi

BASELINE_WORKTREE="$INSTALL_ROOT/hw-gitworktree-baseline-optimized-baseline"
OPTIMIZED_WORKTREE="$INSTALL_ROOT/hw-gitworktree-baseline-optimized-v4"

git -C "$STACK_REPO" fetch origin verl-mini-video-baseline verl-mini-video-optimized-v4

if [ -d "$BASELINE_WORKTREE/.git" ] || [ -f "$BASELINE_WORKTREE/.git" ]; then
  git -C "$BASELINE_WORKTREE" checkout verl-mini-video-baseline
  git -C "$BASELINE_WORKTREE" merge --ff-only origin/verl-mini-video-baseline
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-baseline \
    "$BASELINE_WORKTREE" origin/verl-mini-video-baseline
fi

if [ -d "$OPTIMIZED_WORKTREE/.git" ] || [ -f "$OPTIMIZED_WORKTREE/.git" ]; then
  git -C "$OPTIMIZED_WORKTREE" checkout verl-mini-video-optimized-v4
  git -C "$OPTIMIZED_WORKTREE" merge --ff-only origin/verl-mini-video-optimized-v4
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-optimized-v4 \
    "$OPTIMIZED_WORKTREE" origin/verl-mini-video-optimized-v4
fi

mkdir -p "$HOME/.codex"
touch "$HOME/.codex/config.toml"
if ! grep -q '^\[features\]' "$HOME/.codex/config.toml"; then
  printf '\n[features]\n' >> "$HOME/.codex/config.toml"
fi
if grep -q '^multi_agent_v2 *= *' "$HOME/.codex/config.toml"; then
  sed -i 's/^multi_agent_v2 *= *.*/multi_agent_v2 = true/' "$HOME/.codex/config.toml"
else
  sed -i '/^\[features\]/a multi_agent_v2 = true' "$HOME/.codex/config.toml"
fi

cd "$ADAPTER_REPO"
codex plugin marketplace add .
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local

mkdir -p "$STACK_REPO/.codex"
rm -rf "$STACK_REPO/.codex/agents"
cp -R "$ADAPTER_REPO/.codex/agents" "$STACK_REPO/.codex/agents"

WORK_ORDER_DIR="$STACK_REPO/stacks/verl/mini_video_v4_compare/work-orders"
WORK_ORDER="$WORK_ORDER_DIR/single-node-reference.yaml"
mkdir -p "$WORK_ORDER_DIR"
cat > "$WORK_ORDER" <<YAML
run_id: "mini-video-v4-compare-single-node-reference"
topology_order:
  - "single-node"

model:
  name: "qwen3vl2b"
  path: "<replace-with-shared-model-path>"
dataset:
  train_path: "<replace-with-shared-dataset-path>"
  eval_path: ""
metrics:
  primary_metric: "step_time"
  unit: "seconds"
  source: "training log"
  window: "fixed training step window"

source_release:
  remote: "git@github.com:lchany/hw-gitworktree-baseline-optimized.git"
  sync_policy: "verify_only"
  publish_training_scripts_after_success: false
  publish_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
  management:
    branch: "main"
    worktree: "$STACK_REPO"
  baseline:
    branch: "verl-mini-video-baseline"
    worktree: "$BASELINE_WORKTREE"
    immutable: true
  optimized:
    branch: "verl-mini-video-optimized-v4"
    worktree: "$OPTIMIZED_WORKTREE"
    publish_required_before_run: false

worktree_stack:
  enabled: true
  stack_root: "$STACK_REPO/stacks/verl/mini_video_v4_compare"
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
  allow_training_launch: false
  allow_debug_within_scope: true
  allow_git_commit: false
  allow_git_push: false
  git_push_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
YAML

test -f "$ADAPTER_REPO/.codex/agents/workflow_generalist.toml"
test -f "$ADAPTER_REPO/plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json"
test -f "$ADAPTER_REPO/plugins/verl-subagent-union-workflow/skills/verl-subagent-union-workflow/SKILL.md"
test -f "$STACK_REPO/.codex/agents/workflow_generalist.toml"
test -f "$STACK_REPO/stacks/verl/mini_video_v4_compare/stack.json"
test -f "$STACK_REPO/stacks/verl/mini_video_v4_compare/scripts/switch_stack.py"
test -f "$STACK_REPO/stacks/verl/mini_video_v4_compare/scripts/trainctl.py"
test -f "$STACK_REPO/stacks/verl/mini_video_v4_compare/variants/baseline/container_train_1node.sh"
test -f "$STACK_REPO/stacks/verl/mini_video_v4_compare/variants/optimized-v4/container_train_1node.sh"
test -f "$WORK_ORDER"
test -e "$BASELINE_WORKTREE/.git"
test -e "$OPTIMIZED_WORKTREE/.git"

PLUGIN_VERSION="$(
  python3 - <<PY
import json
from pathlib import Path
p = Path("$ADAPTER_REPO/plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json")
print(json.loads(p.read_text())["version"])
PY
)"

echo "adapter_repo=$ADAPTER_REPO"
echo "stack_repo=$STACK_REPO"
echo "baseline_worktree=$BASELINE_WORKTREE"
echo "optimized_worktree=$OPTIMIZED_WORKTREE"
echo "reference_work_order=$WORK_ORDER"
echo "plugin_version=$PLUGIN_VERSION"
echo "next_command=cd $STACK_REPO && codex"
echo 'next_prompt=$verl-subagent-union-workflow'
```

After the block succeeds, run the smoke test in a new command:

```bash
codex exec --cd "$STACK_REPO" \
  'Spawn the custom agent named workflow_generalist for a smoke test. Do not substitute default, explorer, or worker. The subagent must not run commands or edit files. Require it to return only: role=workflow_generalist and specialized_agent_applicable=false.'
```

### 2.2 Enable Codex Custom Agents

Add this to `~/.codex/config.toml`:

```toml
[features]
multi_agent_v2 = true
```

If you cannot edit the user config, start Codex with the feature flag when testing:

```bash
codex --enable multi_agent_v2
```

### 2.3 Register The Repo Marketplace

Run this from the adapter repository root:

```bash
cd /home/$USER/oh-my-openagent-subagent-adapter
codex plugin marketplace add .
```

This registers `.agents/plugins/marketplace.json`, whose marketplace name is `oh-my-openagent-local`.

### 2.4 Install The Workflow Plugin

```bash
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Confirm the plugin is installed:

```bash
codex plugin list
```

The installed plugin should include `verl-subagent-union-workflow`.

### 2.5 Start A New Codex Thread

Start Codex from the adapter repository root for the first smoke test:

```bash
cd /home/$USER/oh-my-openagent-subagent-adapter
codex
```

Then run:

```text
@VERL Subagent Union Workflow Start the controller and route this as a small workflow-support classification. Use workflow_generalist only; do not run training or edit files.
```

Success criteria:

- The response identifies `workflow_generalist`.
- It does not use `default`, `explorer`, or `worker`.
- It does not run training or edit files.

### 2.6 Verify The Worktree Stack Template

Check that the model-stack repository has the expected template:

```bash
cd /home/$USER/hw-gitworktree-baseline-optimized
ls stacks/verl/mini_video_v4_compare
ls stacks/verl/mini_video_v4_compare/scripts
ls stacks/verl/mini_video_v4_compare/variants/baseline
ls stacks/verl/mini_video_v4_compare/variants/optimized-v4
```

Expected key files:

```text
stacks/verl/mini_video_v4_compare/
  stack.json
  scripts/switch_stack.py
  scripts/trainctl.py
  inventories/59_local_restore.json
  inventories/206.json
  inventories/206_59.json
  inventories/206_59_13_145.json
  variants/baseline/container_train_1node.sh
  variants/baseline/container_train_2node.sh
  variants/baseline/container_train_4node.sh
  variants/baseline/ray_start_*.sh
  variants/optimized-v4/container_train_1node.sh
  variants/optimized-v4/container_train_2node.sh
  variants/optimized-v4/container_train_4node.sh
  variants/optimized-v4/ray_start_*.sh
```

For a new large-model project, copy this stack shape into a new `stacks/verl/<project-name>/` directory and replace the model path, dataset path, containers, inventory, branches, and training commands for that project.

### 2.7 Install Custom Agents Into The Target Management Repository

The workflow plugin provides the controller skill. The executable Codex custom agents must also be available in the target management repository where Codex is launched.

For the reference stack:

```bash
ADAPTER_REPO="/home/$USER/oh-my-openagent-subagent-adapter"
STACK_REPO="/home/$USER/hw-gitworktree-baseline-optimized"

mkdir -p "$STACK_REPO/.codex"
rm -rf "$STACK_REPO/.codex/agents"
cp -R "$ADAPTER_REPO/.codex/agents" "$STACK_REPO/.codex/agents"
test -f "$STACK_REPO/.codex/agents/workflow_generalist.toml"
```

For another model project, copy the same `.codex/agents` directory into that model project's management worktree. Without this step, the controller skill can load but Codex may not be able to spawn `workflow_generalist`, `verl_npu_env_builder`, `baseline_runner`, or the other specialized agents from the target repository.

This creates or updates deployment files in the target management repository. Commit them there when the target project should permanently carry the subagent workflow; otherwise keep them as local deployment state.

### 2.8 Create Baseline And Optimized Worktrees

The reference stack's `stack.json` points to sibling source worktrees. A plain clone of `hw-gitworktree-baseline-optimized` does not create them automatically.

Create them before running the workflow:

```bash
INSTALL_ROOT="/home/$USER"
STACK_REPO="$INSTALL_ROOT/hw-gitworktree-baseline-optimized"
BASELINE_WORKTREE="$INSTALL_ROOT/hw-gitworktree-baseline-optimized-baseline"
OPTIMIZED_WORKTREE="$INSTALL_ROOT/hw-gitworktree-baseline-optimized-v4"

git -C "$STACK_REPO" fetch origin verl-mini-video-baseline verl-mini-video-optimized-v4

if [ -d "$BASELINE_WORKTREE/.git" ] || [ -f "$BASELINE_WORKTREE/.git" ]; then
  git -C "$BASELINE_WORKTREE" checkout verl-mini-video-baseline
  git -C "$BASELINE_WORKTREE" merge --ff-only origin/verl-mini-video-baseline
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-baseline \
    "$BASELINE_WORKTREE" origin/verl-mini-video-baseline
fi

if [ -d "$OPTIMIZED_WORKTREE/.git" ] || [ -f "$OPTIMIZED_WORKTREE/.git" ]; then
  git -C "$OPTIMIZED_WORKTREE" checkout verl-mini-video-optimized-v4
  git -C "$OPTIMIZED_WORKTREE" merge --ff-only origin/verl-mini-video-optimized-v4
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-optimized-v4 \
    "$OPTIMIZED_WORKTREE" origin/verl-mini-video-optimized-v4
fi
```

### 2.9 Generate A Reference Work-Order

Create a reference work-order so the workflow can be invoked immediately after deployment. This work-order is safe by default: it verifies the setup but does not allow training launch or git push until the model and dataset paths are replaced and permissions are deliberately expanded.

```bash
STACK_REPO="/home/$USER/hw-gitworktree-baseline-optimized"
BASELINE_WORKTREE="/home/$USER/hw-gitworktree-baseline-optimized-baseline"
OPTIMIZED_WORKTREE="/home/$USER/hw-gitworktree-baseline-optimized-v4"
WORK_ORDER_DIR="$STACK_REPO/stacks/verl/mini_video_v4_compare/work-orders"
WORK_ORDER="$WORK_ORDER_DIR/single-node-reference.yaml"
mkdir -p "$WORK_ORDER_DIR"

cat > "$WORK_ORDER" <<YAML
run_id: "mini-video-v4-compare-single-node-reference"
topology_order:
  - "single-node"
model:
  name: "qwen3vl2b"
  path: "<replace-with-shared-model-path>"
dataset:
  train_path: "<replace-with-shared-dataset-path>"
  eval_path: ""
metrics:
  primary_metric: "step_time"
  unit: "seconds"
  source: "training log"
  window: "fixed training step window"
source_release:
  remote: "git@github.com:lchany/hw-gitworktree-baseline-optimized.git"
  sync_policy: "verify_only"
  publish_training_scripts_after_success: false
  publish_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
  management:
    branch: "main"
    worktree: "$STACK_REPO"
  baseline:
    branch: "verl-mini-video-baseline"
    worktree: "$BASELINE_WORKTREE"
    immutable: true
  optimized:
    branch: "verl-mini-video-optimized-v4"
    worktree: "$OPTIMIZED_WORKTREE"
    publish_required_before_run: false
worktree_stack:
  enabled: true
  stack_root: "$STACK_REPO/stacks/verl/mini_video_v4_compare"
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
  allow_training_launch: false
  allow_debug_within_scope: true
  allow_git_commit: false
  allow_git_push: false
  git_push_scope:
    - "training_scripts"
    - "ray_scripts"
    - "approved_source_changes"
YAML
```

Before real training, replace the model and dataset paths and intentionally set the relevant permissions to `true`.

### 2.10 Use It From A Target Model Project

After the plugin is installed, open Codex from the target model project's management worktree. For the reference stack, this is:

```bash
cd /home/$USER/hw-gitworktree-baseline-optimized
codex
```

Invoke the workflow explicitly:

```text
$verl-subagent-union-workflow
```

Then provide the work-order path, for example:

```text
Use work-order: stacks/verl/mini_video_v4_compare/work-orders/single-node-reference.yaml
```

The target project must still contain or reference the required stack files:

```text
stacks/verl/<project-name>/
  stack.json
  scripts/switch_stack.py
  scripts/trainctl.py
  inventories/*.json
  variants/baseline/*.sh
  variants/<optimized-variant>/*.sh
```

If these files are missing, the workflow should block in `verl_npu_env_builder` or the controller before launching training.

### 2.11 Non-Interactive CLI Smoke Test

You can also smoke test without opening an interactive Codex session:

```bash
cd /home/$USER/hw-gitworktree-baseline-optimized
codex exec --cd "$PWD" \
  'Spawn the custom agent named workflow_generalist for a smoke test. Do not substitute default, explorer, or worker. The subagent must not run commands or edit files. Require it to return only: role=workflow_generalist and specialized_agent_applicable=false.'
```

If `multi_agent_v2` is not enabled in `~/.codex/config.toml`, add:

```bash
--enable multi_agent_v2
```

to the `codex exec` command.

## 3. Manual Install Reference

Clone both repositories on the target machine:

```bash
git clone https://github.com/lchany/oh-my-openagent-subagent-adapter.git
git clone https://github.com/lchany/hw-gitworktree-baseline-optimized.git
cd oh-my-openagent-subagent-adapter
```

Enable Codex custom-agent dispatch:

```toml
# ~/.codex/config.toml
[features]
multi_agent_v2 = true
```

Install the workflow plugin from the repo-local marketplace:

```bash
codex plugin marketplace add .
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

Install custom agents into the model-stack repository and create the sibling worktrees:

```bash
ADAPTER_REPO="/home/$USER/oh-my-openagent-subagent-adapter"
STACK_REPO="/home/$USER/hw-gitworktree-baseline-optimized"
BASELINE_WORKTREE="/home/$USER/hw-gitworktree-baseline-optimized-baseline"
OPTIMIZED_WORKTREE="/home/$USER/hw-gitworktree-baseline-optimized-v4"

mkdir -p "$STACK_REPO/.codex"
rm -rf "$STACK_REPO/.codex/agents"
cp -R "$ADAPTER_REPO/.codex/agents" "$STACK_REPO/.codex/agents"

git -C "$STACK_REPO" fetch origin verl-mini-video-baseline verl-mini-video-optimized-v4
if [ -d "$BASELINE_WORKTREE/.git" ] || [ -f "$BASELINE_WORKTREE/.git" ]; then
  git -C "$BASELINE_WORKTREE" checkout verl-mini-video-baseline
  git -C "$BASELINE_WORKTREE" merge --ff-only origin/verl-mini-video-baseline
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-baseline "$BASELINE_WORKTREE" origin/verl-mini-video-baseline
fi
if [ -d "$OPTIMIZED_WORKTREE/.git" ] || [ -f "$OPTIMIZED_WORKTREE/.git" ]; then
  git -C "$OPTIMIZED_WORKTREE" checkout verl-mini-video-optimized-v4
  git -C "$OPTIMIZED_WORKTREE" merge --ff-only origin/verl-mini-video-optimized-v4
else
  git -C "$STACK_REPO" worktree add -B verl-mini-video-optimized-v4 "$OPTIMIZED_WORKTREE" origin/verl-mini-video-optimized-v4
fi
```

Start a new Codex thread from the target management repository after installation:

```bash
cd /home/$USER/hw-gitworktree-baseline-optimized
codex
```

Smoke test the subagent route:

```text
@VERL Subagent Union Workflow Start the controller and route this as a small workflow-support classification. Use workflow_generalist only; do not run training or edit files.
```

The result must show `workflow_generalist`. If Codex uses `default`, `explorer`, or `worker` instead, custom-agent dispatch is not correctly enabled.

After the adapter smoke test passes, start Codex from `hw-gitworktree-baseline-optimized` or from the management worktree of the model project derived from that repository.

## 4. Prepare The New Model Project

For a new high-performance model project, use `hw-gitworktree-baseline-optimized` as the structural template. The reference project already demonstrates the required layout under:

```text
stacks/verl/mini_video_v4_compare/
```

Prepare a new git-worktree stack before running the workflow.

Required source layout:

```text
<management-worktree>/
  stacks/verl/<project-name>/
    stack.json
    scripts/switch_stack.py
    scripts/trainctl.py
    inventories/*.json
    variants/baseline/*.sh
    variants/<optimized-variant>/*.sh
<baseline-source-worktree>/
<optimized-source-worktree>/
```

The reference `stack.json` maps each variant to a source worktree, branch, runtime target, and verification markers:

```json
{
  "project": "mini_video_v4_compare",
  "variants": {
    "baseline": {
      "modules": {
        "verl": {
          "source_worktree": "${REPO_PARENT}/hw-gitworktree-baseline-optimized-baseline",
          "branch": "verl-mini-video-baseline",
          "runtime_target": "/vllm-workspace/verl"
        }
      }
    },
    "optimized-v4": {
      "modules": {
        "verl": {
          "source_worktree": "${REPO_PARENT}/hw-gitworktree-baseline-optimized-v4",
          "branch": "verl-mini-video-optimized-v4",
          "runtime_target": "/vllm-workspace/verl"
        }
      }
    }
  }
}
```

For a new model, keep this contract but replace:

- project name
- baseline and optimized branch names
- baseline and optimized source worktree paths
- runtime target if different from `/vllm-workspace/verl`
- marker paths or patterns used to prove baseline absence and optimized presence
- inventory files
- training and Ray startup scripts

Required project decisions before dispatch:

- Baseline branch/worktree is the unoptimized source of truth.
- Optimized branch/worktree contains only the approved optimization changes.
- The runtime source tree, such as `/vllm-workspace/verl`, is a synchronized target, not the source of truth.
- `switch_stack.py` is the only allowed way to switch runtime source between baseline and optimized.
- `trainctl.py` is the only normal training entrypoint used by runners.
- Training/Ray scripts live under the management worktree stack and can be published after successful runs.

Model-specific inputs that must be known:

- Model path readable by every target container or node.
- Dataset path readable by every target container or node.
- Container name per node.
- NPU count and visible device assignment.
- Inventory file for single-node, dual-node, and four-node topologies.
- Baseline and optimized train scripts for each topology.
- Ray startup scripts or shared Ray helper scripts.
- Expected metric name, unit, source log, and comparison window.

## 5. Work-Order Template

Create the work-order content before invoking the workflow. Values below are examples; replace every path and branch for the target model project.

```yaml
run_id: "<project>-<date>-<topology>"
topology_order:
  - "single-node"
  - "dual-node"
  - "four-node"

model:
  name: "<model-name>"
  path: "<shared model path>"
dataset:
  train_path: "<shared dataset path>"
  eval_path: "<optional eval dataset path>"
metrics:
  primary_metric: "<tokens_per_second|samples_per_second|step_time|custom>"
  unit: "<unit>"
  source: "<log path or parser policy>"
  window: "<fixed comparison window>"

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
    worktree: "/home/<user>/hw-gitworktree-baseline-optimized"
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
  stack_root: "/home/<user>/hw-gitworktree-baseline-optimized/stacks/verl/<project-name>"
  inventory: "inventories/<topology>.json"
  nodes: "1|2|4"
  variants:
    baseline: "baseline"
    optimized: "<optimized variant>"
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

Do not include secrets, raw credentials, dense logs, or private keys in the work-order.

For the current reference project, the concrete values are:

```yaml
source_release:
  remote: "git@github.com:lchany/hw-gitworktree-baseline-optimized.git"
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

Use this as a tested example, not as a hardcoded path for every machine.

## 6. Run The Workflow

Invoke the plugin explicitly in Codex:

```text
$verl-subagent-union-workflow
```

Then provide the work-order path or paste the bounded work-order content. The controller must run the phases in this order for each topology:

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

Each runner must launch through:

```bash
python3 scripts/trainctl.py --variant <variant> --nodes <nodes> --inventory <inventory>
```

If `trainctl.py` exists, direct execution of `container_train_*.sh` is invalid unless the work-order explicitly approves a different wrapper.

## 7. What Gets Pushed

Only `source_release_manager` may push, and only when `sync_policy` plus `permissions.allow_git_push` allow it.

Allowed push scope:

- `stacks/**/variants/**/container_train_*.sh`
- `stacks/**/variants/**/ray_start_*.sh`
- `stacks/**/variants/**/ray_start_common.sh`
- `stacks/**/scripts/trainctl.py`
- `stacks/**/scripts/switch_stack.py`
- `stacks/**/stack.json`
- explicitly approved inventory/script changes
- explicitly approved source-code changes in the optimized source worktree

Never push:

- `runs/`
- logs
- metrics summaries
- checkpoints
- debug evidence
- generated reports
- project memory
- dense command output
- datasets
- model files
- unrelated workspace changes

## 8. Acceptance Checklist

Before a new model project is considered ready for this workflow:

- Codex plugin is installed and `workflow_generalist` smoke test passes.
- `hw-gitworktree-baseline-optimized` is cloned or the target model project has copied its stack structure.
- Baseline and optimized source worktrees exist and point to the expected branches.
- Baseline worktree is immutable for optimization code.
- Optimized worktree contains the approved optimization changes.
- `stack.json`, `switch_stack.py`, and `trainctl.py` exist.
- Single-node inventory is present; dual-node and four-node inventories are present when those topologies will run.
- Model and dataset paths are readable inside every target container.
- Required mounts are visible in containers.
- Training and Ray scripts exist for baseline and optimized variants.
- Work-order includes the non-interactive permission envelope.
- Push scope is limited to training scripts, Ray scripts, and explicitly approved source changes.

## 9. Failure Handling

When a phase fails:

- The phase subagent returns `blocked` or `failed` with artifact paths.
- `workflow_supervisor` audits the result.
- `debug_isolator` performs bounded RCA when needed.
- The original failed phase is retried after the fix is verified.
- The controller does not skip forward to a later phase.

If a fix is verified and reusable, perform Experience Vault archive review before advancing.
