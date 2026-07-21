# Background

The desired behavior is for a main OpenCode session to call a custom subagent with the same user-facing mechanism used for built-in subagents:

```ts
task({ subagent_type: "npu-env-builder", load_skills: [], prompt: "..." })
```

The custom agent should also be visible in agent discovery surfaces used by the UI/API layer, not only in a local CLI listing.

## Existing resolution flow

The task tool resolves direct subagent calls through the delegate-task path:

```text
task tool
  -> resolveSubagentExecution()
  -> resolveSubagentAgentMatch()
  -> client.app.agents()
  -> mergeWithClaudeCodeAgents() fallback
  -> findCallableAgentMatch()
```

The fallback merge already included:

- Server/runtime agents from `client.app.agents()`.
- Claude project agents from `.claude/agents`.
- Claude user agents from the user Claude config directory.

The missing piece was OpenCode-style agents from:

- Project `.opencode/agents`.
- User/global OpenCode config `agents` directories.

## Why a patch repository

This repository keeps the upstream source patch separate from local working directories. It gives reviewers a stable artifact containing:

- The exact patch code.
- The background and implementation notes.
- The commands needed to apply and verify the patch.
