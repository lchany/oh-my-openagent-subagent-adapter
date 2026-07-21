# Codex Workflow Operating Guide

## Bootstrap and recovery

When the user asks to install, migrate, restore, inspect, repair, or verify this Codex workflow:

1. Read `docs/codex-workflow-bootstrap-and-recovery.md` completely.
2. Run `scripts/audit_codex_workflow.sh --no-tests` before making changes.
3. Classify every reported item as `PASS`, `MISSING`, or `MISMATCH`.
4. Repair only the earliest missing dependency and rerun the audit; do not skip ahead.
5. Run `scripts/audit_codex_workflow.sh` with tests before declaring the workflow usable.
6. Require a new Codex session launched from this `chatgpt/` directory after marketplace or plugin changes.

Do not read, install, copy, validate, or repair the sibling OpenCode architecture while handling a Codex workflow request. Do not infer marketplace paths, plugin versions, custom-agent files, or cache state from an older environment. Git network synchronization requires an explicit current-turn user request.

Only the main controller interacts with the user. Workflow subagents never ask the user and never create nested agents.
