---
name: tmux-remote-linux
description: Use this whenever the task requires operating, inspecting, testing, or diagnosing a remote Linux environment through a user-prepared tmux pane, especially when you would otherwise run ssh. Replace direct ssh attempts with this skill unless the user explicitly asks for direct SSH. Covers bastion hosts, Kubernetes, logs, services, databases, and production or internal systems.
metadata:
  short-description: Read and write a remote Linux terminal through tmux
---

# tmux Remote Linux

Use the user's prepared tmux pane to operate a remote Linux shell. If you would otherwise run `ssh`, use this skill unless the user explicitly asks for direct SSH.

This skill is for ordinary shell operations. It intentionally avoids REPLs, nested interactive programs, and full-screen TUIs.

## Interface

Scripts default to `REMOTE_TMUX_TARGET=remote:0.0`. Before any script use, the user must explicitly choose the target environment:

```bash
export REMOTE_TMUX_ENV=production
# or
export REMOTE_TMUX_ENV=non-production
```

Do not infer this value. Ask if it is not set or explicitly provided. When the user selects an environment, briefly recommend detaching the managed tmux session after setup (`Ctrl-b d`) and re-attaching only for secrets or intentional takeover.

In `production`, every `send.sh` or `run.sh` command needs explicit user approval. Remind the user that AI can misunderstand shell context, aliases, credentials, kubeconfigs, current directories, and blast radius; the user is responsible for each approved command.

Production chat approval policy for Codex:

For Codex, before each production command:

1. Generate a fresh random digit from `0` to `9`.
2. Show the target, exact command, and one concise Chinese explanation. For temporary-script transfer/execution, also show the script content or a reviewable summary, remote path, and interpreter.
3. Ask the user to reply with only the digit. If the reply is not exactly that digit, do not execute.
4. Use this compact format:
   **生产确认**：**目标** `remote:0.0`
   **说明**：`<one concise Chinese sentence>`
   **命令**：`<command>`
   **同意执行请只回复数字** `<digit>`

If the approval command is too long for one line, put only the command in one fenced block. Do not turn script-like work into a long one-liner to fit the format.
For production approvals, keep commands reviewable; use fenced multi-line blocks for non-trivial commands instead of semicolon-compressed one-liners.

After a matching reply, call the script with one-time approval variables:

```bash
REMOTE_TMUX_ENV=production \
REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT=<digit-shown-to-user> \
REMOTE_TMUX_PROD_APPROVAL_DIGIT=<digit-replied-by-user> \
REMOTE_TMUX_COMMAND_EXPLANATION='<Chinese explanation shown to the user>' \
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh '<command>'
```

Approval is per command. Do not reuse digits or batch unrelated production commands. Never set `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT`, `REMOTE_TMUX_PROD_APPROVAL_DIGIT`, or `REMOTE_TMUX_COMMAND_EXPLANATION` unless the user replied with the matching digit in this conversation.

- Read recent remote terminal output:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/read.sh
$HOME/.codex/skills/tmux-remote-linux/scripts/read.sh 80
```

Reads 40 lines by default. Override with `REMOTE_TMUX_LINES`. It filters obvious wrapper noise unless `REMOTE_TMUX_FILTER_WRAPPER=0`.

- Send one command and press Enter:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/send.sh '<command>'
```

Use only at ordinary Linux shell prompts. Use it for persistent shell state (`cd`, `export`, `sudo -i`) or to start an already-transferred long-running script. Do not use it inside REPLs or to inject large script-like one-liners.

- Run one command with begin/end markers and an exit-code line:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh '<command>'
```

Use for short, bounded, non-interactive shell checks. It base64-transfers one shell command, runs it in a fresh remote `bash` child, returns only this command's output, prints `[exit N]`, and exits locally with the remote status. State changes such as `cd` and `export` do not persist.

`run.sh` uses BEGIN/END markers as the primary command boundary. By default it also installs a short managed bash prompt, `__31D763DA06_TRL_<counter>_<status>__`, and uses the prompt counter only as a recovery guard when markers are missing or stale. Set `REMOTE_TMUX_PROMPT_GUARD=0` to disable this guard. When enabled, treat `PS1` and `PROMPT_COMMAND` in the managed pane as owned by this skill.

Pass the whole shell command as one quoted argument. This is a transport interface, not permission to build complex one-line programs. If the intended command is really a shell or Python script, use the temporary-script workflow below.

- Query local JSONL audit logs:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh last 10
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh failures
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh show <request_id>
```

`logs.sh` requires local `jq`.

Common optional environment variables:

```bash
REMOTE_TMUX_TARGET=remote:0.0
REMOTE_TMUX_ENV=non-production
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40
REMOTE_TMUX_DETECT_INTERACTIVE=1
REMOTE_TMUX_PROMPT_GUARD=1
REMOTE_TMUX_LOG_ENABLED=1
REMOTE_TMUX_LOG_DIR="$HOME/.codex/tmux-remote-linux/logs"
REMOTE_TMUX_REQUEST_ID=<optional-stable-id>
```

`run.sh` and `send.sh` reduce remote shell history noise when possible, but this is not a security boundary. They write local JSONL audit logs by default under `REMOTE_TMUX_LOG_DIR`; use `logs.sh` to inspect them.

If the pane moves to another Linux shell, for example after user-entered SSH credentials or after `tmux-oasis-cli` logs into an instance, the next `run.sh` will install the managed prompt again if needed. Do not run `run.sh` while the pane is still at a password prompt, MFA prompt, Oasis `work>`, or any non-shell prompt.

Prefer the bundled scripts inside this skill directory so the workflow remains self-contained and portable.

## Operating Rules

- Start by reading the pane unless the user gave a precise command to run.
- Treat the tmux pane as shared state. The current prompt, cwd, active kubeconfig, and any running foreground command matter.
- Never send concurrent commands or input to the same tmux target. A tmux pane is a serial interactive channel; wait for one `run.sh`, `send.sh`, or manual recovery action to finish before starting another on that target.
- Prefer `run.sh` for short, non-interactive inspection commands because it gives a scoped output and exit code.
- Prefer `send.sh` for commands expected to run for a long time and commands that intentionally change shell state such as `cd` or `export`.
- Do not force long, script-like, or heavily quoted logic into a single remote one-liner. If it has loops, functions, here-docs, embedded JSON/SQL/awk, nested `ssh`, Python code, or multiple quoting layers, create a local temporary script first.
- For shell logic use `.sh` with `bash`; for Python use `.py` with `python3`. Syntax-check locally when practical (`bash -n`, `python3 -m py_compile`), base64-transfer to a unique remote `/tmp` path, execute with the matching interpreter, preserve the exit code, and remove the remote file.
- Template:

```bash
local_script="$(mktemp -t tmux-remote-linux.XXXXXX.sh)"  # or .py
# write script locally, then optionally: bash -n "$local_script" or python3 -m py_compile "$local_script"
encoded="$(base64 < "$local_script" | tr -d '\n')"
remote_script="/tmp/$(basename "$local_script")"
remote_interpreter="bash"  # or python3
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh "printf '%s' '$encoded' | base64 -d > '$remote_script' && chmod 700 '$remote_script' && $remote_interpreter '$remote_script'; status=\$?; rm -f '$remote_script'; exit \$status"
```

  Keep script output bounded and do not put secrets in the local file or remote `/tmp` script. In production, approval must cover the script content or summary, remote path, interpreter, and impact.
- The managed pane must not enter agent control while it is inside an interactive CLI, REPL, or TUI. If it is already in one, stop and ask the user to exit or handle it manually before continuing.
- Do not operate MySQL, Redis, Spark shell, psql, Python REPL, Node REPL, Oasis `work>`, attached container shells, or similar prompts through this skill. Use one-shot non-interactive commands or the dedicated skill that owns that CLI, including for exits.
- Bound unknown output. Do not dump unknown-size files, logs, or command results unless the user explicitly asks for full output.
- Prefer limited reads: `sed -n '1,120p' file`, `tail -n 100`, keyword/time filters, `journalctl -n --no-pager`, `docker logs --tail`, or `kubectl logs --tail`; check `ls -lh`/`wc` only when full content is needed.
- Avoid full-screen TUI programs such as `vim`, `nano`, `less`, `top`, `htop`, and `watch`; use bounded non-interactive commands instead, or ask the user to handle the TUI and report when it is ready.
- If `run.sh` refuses because it detected an interactive prompt, do not disable the detector; ask the user to exit or handle the REPL manually.
- For slow remote commands, wait and poll. Network, cold reads, package pulls, and K8s operations may be slow. Do not rush to `Ctrl-C`.
- Only send `Ctrl-C`, `pkill`, `kill`, `umount`, `helm upgrade`, `kubectl delete`, or similar disruptive commands when the user asks, clearly approves, or the terminal is unusable and recovery is necessary.
- If a pending `run.sh` was interrupted and later reports a stale marker, use `read.sh`. If the pane is clearly back at a normal Linux shell prompt, it is acceptable to clear pane history once with `tmux clear-history -t "${REMOTE_TMUX_TARGET:-remote:0.0}"` and retry.
- Treat destructive or hard-to-reverse operations as requiring explicit confirmation. This includes deletion, truncation, overwrites, cache clearing, service restarts, and test-data cleanup.
- In production, every command needs the chat approval flow above, even if it looks read-only. Do not rely on command prefixes to decide business risk.
- If a command opens a continuation prompt such as `>`, recover with `tmux send-keys -t "$REMOTE_TMUX_TARGET" C-c` only after confirming it is an accidental broken shell state.
- Never edit local repository code unless the user explicitly asks. This skill is for remote terminal operation.

## Disclaimer

Use this skill at your own risk. The user is responsible for reviewing commands and their impact.

## If The Remote Terminal Is Not Ready

If `read.sh` shows no usable remote shell, ask the user to:

- open or attach a tmux session named `remote`, or set `REMOTE_TMUX_TARGET` to the correct pane
- log into the target remote machine
- run any required setup there, such as `cd`, `export KUBECONFIG=...`, proxy settings, credentials, or environment activation

Then use `read.sh` again. Do not guess target hosts or credentials.

## Reporting

Summarize the important remote output in the final answer because the user may not see raw tool output. Include:

- The remote host, cwd, or context if visible.
- Whether the command completed, is still running, or was interrupted.
- Key metrics or errors.
- Any action taken that changed remote state.
