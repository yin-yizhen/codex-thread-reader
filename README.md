# codex-thread-reader

`codex-thread-reader` 是一个 Codex skill，用来把 `codex://threads/...` 或裸 thread id 变成可复用的本地对话上下文。

当你把一个 Codex 对话 id 发给另一个 agent 时，这个 skill 会帮助它在本地 Codex 记录中找到对应的 JSONL 会话文件，读取用户和 assistant 的可读消息，并整理成摘要、时间线或可继续工作的上下文。

## 应用场景

### 从另一个聊天继续工作

你已经和一个 agent 讨论过实现方案、调试路径、产品思路或研究方向，后来又打开了新聊天。把旧 thread id 发给新 agent，它可以接着之前的结论继续。

示例：

```text
Use $codex-thread-reader to read codex://threads/019e3a3d-a826-76c3-a124-89f96ae589d3 and continue from the last open question.
```

### 合并多个 agent 的建议

你可能在几个不同聊天里分别问过 PDF RAG、GraphRAG、前端交互、部署方案。这个 skill 可以让新 agent 读取这些记录，把分散的建议合成一个更完整的判断。

示例：

```text
读取这三个 Codex thread id，比较它们对 RAG 架构的建议，并合成一个最终方案。
```

### 找回之前做过的技术判断

你记得某个 agent 推荐过一个库、一个参数、一个架构选择或一条命令，但不想手动翻完整聊天记录。

示例：

```text
读取这个 thread，找出里面关于 metadata、embedding 和表格 chunking 的内容。
```

### 把长对话整理成执行计划

很多讨论会夹杂需求、约束、结论和待办事项。这个 skill 可以让 agent 把旧聊天整理成 phase plan、TODO、issue 列表或实现说明。

示例：

```text
读取这个 thread，把里面已经确定的方案整理成实施阶段。
```

### 检查对话在哪里发生了偏移

长对话里，agent 有时会逐渐偏离最初的问题。读取会话后，可以按时间线复盘用户问题和 assistant 回复，找出语义变化的位置。

示例：

```text
读取这个 thread，告诉我 agent 是从哪里开始回答另一个问题的。
```

### 恢复中断的调试过程

如果前一个聊天已经跑过命令、看过文件、定位过错误，新 agent 可以通过旧记录知道已经尝试过什么，避免重复排查。

示例：

```text
读取这个 thread，总结已经运行过的命令和下一步调试建议。
```

### 为项目建立轻量上下文记忆

一个项目往往会有多个 Codex 聊天。把相关 thread id 交给 agent 后，它可以整理之前讨论过的设计选择、未解决问题和反复出现的决策。

示例：

```text
读取我贴的这些 thread id，总结这个项目目前已经确定的技术路线。
```

## 它会读取什么

脚本默认读取本地 Codex Desktop 会话记录，常见位置是：

```text
D:\codex_home\session_index.jsonl
D:\codex_home\sessions
D:\codex_home\archived_sessions
```

它会提取：

- thread id
- 会话标题
- 工作区 cwd
- 本地 JSONL 文件路径
- 用户消息
- assistant 回复
- 可选的工具调用记录
- 关于加密 reasoning 的提示

它不会解密 `encrypted_content`，也不会声称自己能读取隐藏推理。

## 使用方式

在 Codex 中可以这样调用：

```text
Use $codex-thread-reader to read codex://threads/<thread-id>.
```

也可以直接运行脚本：

```powershell
& ".\scripts\read_codex_thread.ps1" `
  -ThreadId "codex://threads/019e3a3d-a826-76c3-a124-89f96ae589d3" `
  -CurrentCwd "D:\codex-study\rag-project"
```

如果需要查看工具调用记录，可以加 `-IncludeToolEvents`：

```powershell
& ".\scripts\read_codex_thread.ps1" `
  -ThreadId "019e3a3d-a826-76c3-a124-89f96ae589d3" `
  -IncludeToolEvents
```

## 安全边界

- 只读设计。
- 不删除、不改写、不归档任何会话记录。
- 跳过加密 reasoning。
- 默认只整理用户和 assistant 的消息，不主动倾倒 system/developer 提示词。
- 传入 `-CurrentCwd` 后，会检查恢复到的会话是否属于当前工作区。
- 不应暴露无关本地配置或认证文件里的敏感信息。

## 仓库内容

```text
SKILL.md
agents/openai.yaml
scripts/read_codex_thread.ps1
```

## 验证

这个 skill 已通过 Codex skill creator 校验：

```text
Skill is valid!
```

脚本也用真实本地 Codex thread id 测试过，可以返回会话标题、cwd 匹配状态、可读消息数量，以及加密 reasoning 跳过提示。
