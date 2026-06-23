# oh-my-openagent subagent adapter

This repository packages a small patch for `oh-my-openagent` / `oh-my-opencode` that lets `task(subagent_type="...")` resolve custom OpenCode agents from `.opencode/agents` in the same fallback path that already resolves Claude-style agents.

## What this solves

In the target codebase, the real OpenCode runtime can load custom agents from `.opencode/agents`, and `opencode agent list` can show them. The `task` delegation fallback path, however, only merged Claude-style project/user agents when `client.app.agents()` did not provide the desired agent. That made custom OpenCode subagents easier to lose in main-session delegation paths and UI/API wrappers that depend on task-callable agent resolution.

This patch adds OpenCode project/global agent loaders to the delegate-task fallback merge and adds focused regression tests for that behavior.

## Files changed upstream

The patch changes these upstream files:

- `packages/omo-opencode/src/tools/delegate-task/subagent-discovery.ts`
- `packages/omo-opencode/src/tools/delegate-task/subagent-discovery.test.ts` (new)

No local machine paths, container names, secrets, or private config are required by the patch.

## Apply the patch

From a clean checkout of `oh-my-openagent`:

```bash
git checkout dev
git pull
git apply /path/to/oh-my-openagent-subagent-adapter/patches/0001-enable-opencode-agent-fallback-for-task.patch
```

Then verify:

```bash
bun test packages/omo-opencode/src/tools/delegate-task/subagent-discovery.test.ts
opencode agent list
```

For a real custom subagent smoke test, put an agent file under the target project's `.opencode/agents/<name>.md`, restart the OpenCode session/runtime if needed, then call:

```ts
task({ subagent_type: "<name>", load_skills: [], prompt: "Return exactly: ok" })
```

## Documentation

- `docs/background.md`: why the patch exists and what path it changes.
- `docs/implementation.md`: exact code-level change and resolution order.
- `docs/apply-patch.md`: detailed patch and verification workflow.
