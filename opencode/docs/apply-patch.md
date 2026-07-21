# Apply and verify the patch

## Prerequisites

- A clean checkout of `oh-my-openagent` or `oh-my-opencode`.
- Bun available in the target checkout for the unit test.
- OpenCode installed for end-to-end smoke verification.

## Apply

From the upstream checkout:

```bash
git status --short
git apply /path/to/repository/opencode/versions/v1/patches/0001-enable-opencode-agent-fallback-for-task.patch
```

If the patch does not apply, inspect the target file around:

```text
packages/omo-opencode/src/tools/delegate-task/subagent-discovery.ts
```

The patch expects that file to contain `mergeWithClaudeCodeAgents()` and imports from `../../features/claude-code-agent-loader`.

## Unit test

Run the focused regression test:

```bash
bun test packages/omo-opencode/src/tools/delegate-task/subagent-discovery.test.ts
```

If the repository requires the full gate, also run the upstream test/build commands documented in its `AGENTS.md`.

## Manual OpenCode smoke test

Create or use a project-level custom agent:

```text
<project>/.opencode/agents/npu-env-builder.md
```

Then verify discovery:

```bash
opencode agent list | rg "npu-env-builder"
```

Finally, from a main session, invoke the subagent through the task tool:

```ts
task({
  subagent_type: "npu-env-builder",
  load_skills: [],
  prompt: "Return exactly: npu-env-builder-ok",
})
```

Expected result:

```text
npu-env-builder-ok
```

## Roll back

Before committing upstream, rollback is just:

```bash
git apply -R /path/to/repository/opencode/versions/v1/patches/0001-enable-opencode-agent-fallback-for-task.patch
```
