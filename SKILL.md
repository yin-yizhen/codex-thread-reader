---
name: codex-thread-reader
description: Read and summarize saved local Codex conversation records. Use when the user provides a codex thread URL, a bare Codex thread/session id, or asks to find, inspect, continue from, compare, extract context from, or summarize another Codex agent conversation in the local Codex workspace.
---

# Codex Thread Reader

Use this skill to recover useful context from local Codex Desktop session records. Treat the records as read-only evidence: locate the session, parse the saved messages, and report what can be known without claiming access to hidden model reasoning.

## Quick Start

Prefer the bundled PowerShell script:

```powershell
& "<skill-dir>\scripts\read_codex_thread.ps1" -ThreadId "<codex-thread-url-or-id>" -CurrentCwd "<current workspace cwd>"
```

The script returns JSON with the resolved thread id, session title, cwd, file path, user/assistant messages, and warnings. Parse that JSON before answering.

If the user asks for a concise answer, summarize the returned messages. If they ask for the full readable record, list the user and assistant messages in timestamp order. Do not dump system/developer prompts or tool outputs unless the user explicitly asks for operational details.

## Workflow

1. Extract the id from the user input.
   - Accept `codex://threads/<id>`.
   - Accept a bare UUID-like Codex id such as `019e3a3d-a826-76c3-a124-89f96ae589d3`.
2. Run `scripts/read_codex_thread.ps1`.
   - Pass `-CurrentCwd` when the current workspace path is known.
   - Add `-IncludeToolEvents` only when tool calls or outputs are relevant.
   - Add `-IncludeSystemMessages` only when the user explicitly asks for prompts/instructions.
3. Verify the returned `cwd_match`.
   - If `false`, say the record was found but belongs to another workspace.
   - Continue only if that still matches the user's intent.
4. Explain coverage and limits.
   - Local user/assistant messages can be read when saved in JSONL.
   - `encrypted_content` cannot be decrypted.
   - Missing or remote-only records cannot be recovered from local files.
5. Produce the requested output.
   - For "find the record": give title, path, cwd, updated time, and message count.
   - For "summarize": provide the core discussion, decisions, open questions, and current stopping point.
   - For "continue from it": extract the actionable context and continue from the newest relevant user request.
   - For "read the full record": list readable user/assistant messages in order, avoiding hidden reasoning and long internal prompts unless requested.

## Output Rules

- Prefer summaries over raw dumps unless the user asks for complete readable messages.
- Quote only user/assistant conversation content needed for the answer.
- Do not claim to read chain-of-thought or decrypted reasoning.
- Do not modify, delete, archive, or rewrite session files.
- Do not expose auth tokens, config secrets, or unrelated local records.
- Deduplicate repeated user messages when presenting a clean conversation summary.

## Manual Fallback

If the script cannot run, search manually:

```powershell
rg -n --fixed-strings "<thread-id>" "D:\codex_home\session_index.jsonl" "D:\codex_home\sessions" "D:\codex_home\archived_sessions"
```

Then open the matching `.jsonl` with UTF-8, parse each line as JSON, and extract:

- `session_meta.payload.id`, `cwd`, `timestamp`
- `response_item.payload.type == "message"` for user/assistant messages
- `event_msg.payload.type == "user_message"` only if response items are absent

Skip encrypted reasoning records.
