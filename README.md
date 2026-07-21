# Agent workflow architectures

This repository keeps the two agent runtimes physically separate:

- [`chatgpt/`](chatgpt/README.md): the local Codex/ChatGPT multi-agent workflow, Codex agents, plugin, tests, and versioned patches.
- [`opencode/`](opencode/README.md): the OpenCode agent workflow, OpenCode adapter patches, agents, skills, and documentation.

Run, install, validate, and version each architecture from its own directory. Files in one architecture must not import, discover, patch, package, or validate files from the other architecture.

The repository root contains only shared repository policy and this architecture index. Runtime state is not a shared input between the two implementations.
