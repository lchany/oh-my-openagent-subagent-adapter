# Implementation details

## Target upstream module

The patch targets:

```text
packages/omo-opencode/src/tools/delegate-task/subagent-discovery.ts
```

That module owns fallback agent merging and task-callable agent filtering for direct subagent delegation.

## Code change

The patch imports two existing loader functions from the Claude/OpenCode compatibility loader barrel:

```ts
loadOpencodeProjectAgents(directory)
loadOpencodeGlobalAgents()
```

It then adds their records to `mergeWithClaudeCodeAgents()`.

## Resolution order after patch

The merged task-callable list is built in this order:

1. Runtime/server agents from `client.app.agents()`.
2. Claude project agents.
3. OpenCode project agents.
4. Claude user agents.
5. OpenCode global agents.

The existing first-wins de-duplication remains unchanged. That preserves runtime/server agents as the highest-priority source and avoids overriding built-ins with same-name local files.

## Test coverage

The patch adds a focused test file:

```text
packages/omo-opencode/src/tools/delegate-task/subagent-discovery.test.ts
```

The tests mock the loader barrel and assert that `mergeWithClaudeCodeAgents()` plus `findCallableAgentMatch()` can resolve:

- An OpenCode project subagent.
- An OpenCode global subagent.

The test is intentionally scoped to `subagent-discovery.ts` instead of expanding the already-large resolver test file.

## Expected user-visible result

After applying the patch and restarting the OpenCode runtime if needed, custom agents placed under `.opencode/agents` should be available to main-session `task(subagent_type="...")` resolution when the delegate-task fallback path is used.
