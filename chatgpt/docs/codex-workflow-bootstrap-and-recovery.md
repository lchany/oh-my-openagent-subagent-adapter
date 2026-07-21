# Codex 工作流新环境搭建与旧环境恢复指南

## 1. 文档目标

本指南只适用于当前目录中的 Codex/ChatGPT 架构。它指导 LLM 或人工操作者完成两类任务：

1. 在新环境中，从源码目录开始安装工作流，直到 Codex 能发现五个自定义 Agent、加载插件并通过完整验证。
2. 在旧环境中，只读检查每个依赖层，确定缺失或指向错误的步骤，然后按照依赖顺序逐项修复。

本指南恢复的是“工作流架构可用性”，不是训练状态。默认 `resume_policy=fresh_start`，不得自动恢复旧训练 step、checkpoint、优化器、Ray 会话、启动脚本或输出目录。确需恢复训练时，必须在新的完整 intake 中确认准确的恢复来源。

## 2. 唯一架构根目录

先进入 `chatgpt/`：

```bash
cd /absolute/path/to/repository/chatgpt
export CODEX_WORKFLOW_ROOT="$PWD"
```

后续命令中的 `$CODEX_WORKFLOW_ROOT` 必须指向包含以下目录的绝对路径：

```text
chatgpt/
├── .agents/plugins/marketplace.json
├── .codex/agents/
├── AGENTS.md
├── plugins/verl-subagent-union-workflow/
├── scripts/audit_codex_workflow.sh
├── tests/
└── versions/
```

不得把仓库根目录、其他项目目录或其他 Agent 运行时目录当成 `CODEX_WORKFLOW_ROOT`。

## 3. 恢复顺序

无论新环境还是旧环境，都按以下依赖顺序处理：

```text
命令依赖
→ ChatGPT 架构源码
→ 五个 Codex Agent
→ 插件 manifest
→ marketplace 文件及相对路径
→ Codex marketplace 注册
→ 插件安装与启用
→ 插件缓存和源码一致
→ 完整测试
→ 新 Codex 会话加载
→ 只读工作流冒烟确认
```

后面的步骤依赖前面的步骤。发现缺失后，只修复最前面的失败项，然后重新审计。

## 4. 新环境从零搭建

### 4.1 放置源码

把本项目完整放到新环境。可以使用已经审核过的本地副本、压缩包或用户明确授权的 Git 操作。本指南不会自行决定远端地址，也不会自行执行 `git pull`、`git fetch` 或 `git push`。

确认当前目录：

```bash
cd "$CODEX_WORKFLOW_ROOT"
test -s AGENTS.md
test -s .agents/plugins/marketplace.json
test -d .codex/agents
test -s plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json
```

### 4.2 检查基础命令

```bash
codex --version
git --version
python3 --version
bash --version | head -n 1
rg --version | head -n 1
sha256sum --version | head -n 1
```

缺少任一命令时，先安装对应工具。不要继续注册 marketplace，因为后续诊断结果会不完整。

### 4.3 第一次只读审计

```bash
./scripts/audit_codex_workflow.sh --no-tests
```

新环境通常会在 marketplace 注册、插件安装或缓存步骤显示 `MISSING`。这属于预期状态。

### 4.4 注册本地 marketplace

先查看当前注册：

```bash
codex plugin marketplace list
```

本项目 marketplace 名称为 `oh-my-openagent-local`，正确根目录必须等于 `$CODEX_WORKFLOW_ROOT`。

如果尚未注册：

```bash
codex plugin marketplace add "$CODEX_WORKFLOW_ROOT"
```

如果同名 marketplace 指向旧路径，先确认输出中的目标确实是本项目旧路径，再执行：

```bash
codex plugin marketplace remove oh-my-openagent-local
codex plugin marketplace add "$CODEX_WORKFLOW_ROOT"
```

不要直接修改 Codex 全局 `config.toml`，使用 marketplace 子命令维护注册状态。

### 4.5 安装插件

```bash
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
codex plugin list
```

预期状态同时包含：

```text
verl-subagent-union-workflow@oh-my-openagent-local
installed, enabled
```

列出的版本必须与以下文件中的 `version` 一致：

```text
plugins/verl-subagent-union-workflow/.codex-plugin/plugin.json
```

### 4.6 运行完整验证

```bash
./scripts/audit_codex_workflow.sh
```

最终必须输出：

```text
READY: source, agents, marketplace, plugin, cache, and validation are usable.
```

如果显示 `NOT READY`，转到第 6 节按输出类型修复。

### 4.7 启动新的 Codex 会话

插件、Agent 文件和 `AGENTS.md` 都在会话启动时发现。完成安装或修复后，关闭旧会话，从本目录启动新会话：

```bash
cd "$CODEX_WORKFLOW_ROOT"
codex
```

不要用修复前已经打开的会话判断安装是否成功。

### 4.8 只读冒烟确认

在新会话中调用工作流，但明确禁止执行训练或环境变更：

```text
使用 $verl-subagent-union-workflow，只读列出主控制器、五个阶段角色、完整 intake 门禁和默认策略；不要创建目录、容器、Ray 或训练进程。
```

预期角色：

```text
baseline_runner
optimized_runner
workflow_supervisor
benchmark_comparator
experiment_reporter
```

预期默认策略：

```text
resume_policy=fresh_start
step_result_policy=final_only
max_attempts=20
```

只有角色、门禁和默认策略均正确，工作流才算可用。

## 5. 旧环境逐步检查

### 5.1 保持只读

先运行：

```bash
cd "$CODEX_WORKFLOW_ROOT"
./scripts/audit_codex_workflow.sh --no-tests
```

审计脚本不会注册 marketplace、安装插件、修改源码或清理缓存。它只报告状态。

### 5.2 读取审计结果

状态含义：

| 状态 | 含义 | 处理方式 |
|---|---|---|
| `PASS` | 当前层满足要求 | 保留，不重复修改 |
| `MISSING` | 文件、命令、注册、安装或缓存不存在 | 按第 6 节补齐该层 |
| `MISMATCH` | 对象存在但路径、版本、内容或数量错误 | 先确认旧值，再定向修正 |
| `INFO` | 非阻断说明 | 阅读后继续 |

### 5.3 修复一个步骤后立即复查

每次只处理最早出现的一个 `MISSING` 或 `MISMATCH`：

```bash
./scripts/audit_codex_workflow.sh --no-tests
```

所有快速检查通过后再运行：

```bash
./scripts/audit_codex_workflow.sh
```

这样可以避免用后续安装动作掩盖前面的源码或路径错误。

## 6. 缺失项与修复动作

### 6.1 `command unavailable`

安装对应命令后重新审计。不要用别名或另一个容器中的命令代替当前环境命令。

### 6.2 `architecture directories are absent`

当前目录不是完整的 `chatgpt/` 架构，或者复制不完整。重新取得完整目录；不要从其他运行时目录拼接 Agent 或 Skill。

### 6.3 Agent 数量或字段不匹配

必须恰好存在五个 `.toml` 文件，每个文件包含 `name`、`description` 和 `developer_instructions`。从当前项目同一版本恢复整个 `.codex/agents/`，不要逐个从旧环境凑文件。

### 6.4 插件 manifest 缺失或无效

恢复完整的：

```text
plugins/verl-subagent-union-workflow/
```

不要只复制 `SKILL.md`；`.codex-plugin/plugin.json`、`agents/openai.yaml` 和脚本必须来自同一版本。

### 6.5 marketplace JSON 缺失或路径错误

确认 `.agents/plugins/marketplace.json` 中：

```text
name = oh-my-openagent-local
plugin = verl-subagent-union-workflow
source = local
source.path = ./plugins/verl-subagent-union-workflow
```

`source.path` 相对于 `chatgpt/` 根目录解析，不相对于 `.agents/plugins/` 目录解析。

### 6.6 marketplace 未注册或指向旧目录

执行第 4.4 节。删除同名注册前必须先通过 `codex plugin marketplace list` 确认它确实指向错误目录。

### 6.7 插件未安装、未启用或版本不一致

重新执行：

```bash
codex plugin add verl-subagent-union-workflow@oh-my-openagent-local
```

如果插件源码刚更新，先按照项目发布流程更新插件 cachebuster，再重新安装。不要手工修改 Codex 插件缓存。

### 6.8 插件缓存与源码不一致

先核对 marketplace 根目录和插件版本。如果两者正确，重新执行插件安装。缓存目录属于安装结果，不是源码；不要用缓存覆盖 `chatgpt/plugins/`。

### 6.9 完整测试失败

查看：

```bash
sed -n '1,200p' /tmp/codex-workflow-validation.out
```

修复测试指出的最早失败项，然后重新运行完整审计。测试包括：Agent 规则、插件结构、intake、精确 NPU 绑定、终态清理、版本补丁、缓存一致性和架构隔离。

### 6.10 全部通过但旧会话看不到插件或 Agent

这是会话加载边界问题。按第 4.7 节从 `chatgpt/` 目录启动新 Codex 会话，再执行只读冒烟确认。

## 7. LLM 自动恢复协议

当 LLM 接手一个未知或旧环境时，必须使用以下固定流程：

1. 确认用户要求恢复的是 Codex 工作流架构，而不是训练状态。
2. 定位绝对 `chatgpt/` 根目录，不从历史会话猜测路径。
3. 完整阅读本指南。
4. 运行 `audit_codex_workflow.sh --no-tests`。
5. 汇总所有结果，但只修复依赖顺序中最早的失败项。
6. 每次修复后重新只读审计。
7. 快速审计全通过后运行完整审计。
8. 完整审计通过后要求从 `chatgpt/` 启动新会话。
9. 在新会话执行只读冒烟确认。
10. 只有看到 `READY` 且冒烟输出正确，才能报告“工作流可用”。

禁止行为：

- 不得因为看到旧 checkpoint 就恢复训练。
- 不得从其他项目或其他 Agent 运行时复制配置。
- 不得让子 Agent 向用户提问或创建嵌套 Agent。
- 不得跳过模型、数据集、工作目录、容器、拓扑和精确 NPU 分配的完整 intake。
- 不得在未得到用户当前授权时执行 Git 网络同步。

## 8. 可用性判定

只有同时满足以下条件才判定可用：

- 审计脚本完整模式返回退出码 `0` 和 `READY`。
- marketplace 根目录为当前 `chatgpt/` 绝对路径。
- 插件为 `installed, enabled`，源码与缓存一致。
- 五个项目级自定义 Agent 完整存在。
- 新会话从 `chatgpt/` 目录启动。
- 只读冒烟确认返回正确角色、intake 门禁和默认策略。

满足这些条件只代表工作流架构可用。正式训练仍必须由主控制器完成当前运行的完整 intake 确认。
