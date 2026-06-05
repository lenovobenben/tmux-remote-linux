---
name: tmux-remote-linux
description: Use this whenever the task requires operating, inspecting, testing, or diagnosing a remote Linux environment through a user-prepared tmux pane, especially when you would otherwise run ssh. Replace direct ssh attempts with this skill unless the user explicitly asks for direct SSH. Covers bastion hosts, Kubernetes, logs, services, databases, and production or internal systems.
metadata:
  short-description: Read and write a remote Linux terminal through tmux
---

# tmux Remote Linux

Use the user's tmux bridge when the task is about operating a remote Linux terminal that the user has opened locally. If you would otherwise run `ssh`, use this skill instead unless the user explicitly asks for direct SSH. This skill is a generic terminal transport: read remote output, send commands, and report results.

Reliability is more important than broad terminal interactivity. This skill intentionally avoids high-interaction command-line programs and full-screen terminal UIs.

## Interface

The scripts default to tmux target `remote:0.0`. Override it with `REMOTE_TMUX_TARGET` when the user has multiple remote panes.

Before any script use, the user must explicitly choose the target environment:

```bash
export REMOTE_TMUX_ENV=production
# or
export REMOTE_TMUX_ENV=non-production
```

Do not infer this value. Ask the user if it is not already set or explicitly provided. In `production` mode, every command sent through `send.sh` or `run.sh` must stop for explicit user confirmation. Interactive CLI confirmation shows a warning with `!!!`; chat-approved commands stay quiet because the chat prompt already showed the production approval. In `non-production` mode, commands may run without production confirmation.

When the user selects the environment, briefly recommend detaching the managed tmux session after setup (`Ctrl-b d`) and re-attaching only for secrets or intentional takeover.

Production warning policy: when the user selects `production`, remind them to be extremely careful with AI-assisted remote operations. AI can misunderstand shell context, stale panes, aliases, credentials, kubeconfigs, current directories, and blast radius. Make clear that the user is responsible for each command they approve.

Production chat approval policy for Codex:

1. Before every production `send.sh` or `run.sh` command, generate a fresh random digit from `0` to `9`.
2. Show the user the target, exact command, and a clear Chinese explanation of what the command will do and why it is needed.
3. Keep the approval prompt compact. Do not add blank lines between the explanation, target, command, and approval digit. Put target and explanation on one line. Put the command on its own line so it is easy to scan. Put the approval digit at the end of the approval sentence on that same command line. Use only Markdown styles that render reliably in Codex terminal output: bold labels and inline-code values. Do not use HTML tags or inline CSS; they may be printed literally.
4. Use this rendered Markdown format, not a fenced code block:
   **生产确认**：**目标** `remote:0.0`。**说明**：`<one concise Chinese sentence>`
   **命令**：`<command>`。**同意执行请只回复数字** `<digit>`

5. If the command is too long for one line, keep the command in one fenced code block and put the approval sentence immediately after it without extra blank lines.
6. Ask the user to reply with only that digit if they approve this exact command.
7. If the user's reply is not exactly the digit, do not execute the command. Start over with a new digit if the command is still needed.
8. After a matching reply, call the script with these environment variables for that one command:

```bash
REMOTE_TMUX_ENV=production \
REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT=<digit-shown-to-user> \
REMOTE_TMUX_PROD_APPROVAL_DIGIT=<digit-replied-by-user> \
REMOTE_TMUX_COMMAND_EXPLANATION='<Chinese explanation shown to the user>' \
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh '<command>'
```

The approval is per command. Do not reuse a digit for a later command. Do not batch unrelated production commands under one approval.

**Anti-bypass rule**: You MUST NOT set `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT`, `REMOTE_TMUX_PROD_APPROVAL_DIGIT`, or `REMOTE_TMUX_COMMAND_EXPLANATION` yourself unless the user has explicitly replied with the approval digit in the current conversation. These variables are a relay of the user's informed consent, not a way to skip the approval step. Setting them without a matching user reply is a protocol violation, even for seemingly harmless commands like `exit`, `cd`, or read-only queries.

- Read recent remote terminal output:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/read.sh
$HOME/.codex/skills/tmux-remote-linux/scripts/read.sh 80
```

`read.sh` reads 40 lines by default. Override the default with `REMOTE_TMUX_LINES`. It filters obvious Codex marker lines and full Codex wrapper command lines by default; set `REMOTE_TMUX_FILTER_WRAPPER=0` only when debugging the transport itself.

- Send one command and press Enter:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/send.sh '<command>'
```

`send.sh` is for Linux shell prompts only. It may add shell-only history cleanup wrapping, so it must not be used inside non-shell interactive CLIs such as `mysql>`, `python>>>`, `spark-sql>`, `redis>`, or Oasis `work>`. Even simple inputs such as `exit`, `quit`, `bye`, or `\q` belong to the skill that owns that CLI.

- Run one command with begin/end markers and an exit-code line:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh '<command>'
```

`run.sh` sends the command through base64, executes it in a remote `bash` child process, waits briefly, captures recent pane output, and prints only the output between its unique markers. It appends `[exit N]` when the end marker is visible, and the local script exits with the remote command's exit code. It does not dump old pane history if its begin marker is missing. For long-running commands, if the end marker is not visible yet, wait and call `read.sh` to inspect progress rather than interrupting.

Pass the whole shell command as one quoted argument. If `run.sh` or `send.sh` receives extra arguments, it exits with usage instead of guessing how to join them.

Important: `run.sh` always starts a fresh non-interactive `bash` child. Do not use it to query or control state that only exists inside the current interactive program, such as `mysql>`, `redis-cli`, `spark-shell>`, `psql>`, a Python REPL, a Node REPL, an attached container shell, or shell in-memory history. Use `read.sh` to identify and report the current prompt, then ask the user to exit or handle that REPL manually.

- Query local JSONL audit logs:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh last 10
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh failures
$HOME/.codex/skills/tmux-remote-linux/scripts/logs.sh show <request_id>
```

`logs.sh` requires local `jq`.

Useful optional environment variables:

```bash
REMOTE_TMUX_TARGET=remote:0.0
REMOTE_TMUX_ENV=non-production
REMOTE_TMUX_FILTER_WRAPPER=1
REMOTE_TMUX_RUN_WAIT_SECONDS=1
REMOTE_TMUX_RUN_CAPTURE_LINES=400
REMOTE_TMUX_RUN_MARKER_CAPTURE_LINES=5000
REMOTE_TMUX_RUN_BEGIN_TIMEOUT_SECONDS=5
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40
REMOTE_TMUX_DETECT_INTERACTIVE=1
REMOTE_TMUX_AVOID_REMOTE_HISTORY=1
REMOTE_TMUX_LOG_ENABLED=1
REMOTE_TMUX_LOG_DIR="$HOME/.codex/tmux-remote-linux/logs"
REMOTE_TMUX_LOG_MAX_OUTPUT_LINES=10
REMOTE_TMUX_LOG_RETENTION_DAYS=7
REMOTE_TMUX_REQUEST_ID=<optional-stable-id>
```

By default, `run.sh` and `send.sh` reduce remote shell history noise by prefixing sent commands with history-ignore settings and a leading space, then deleting the just-sent history entry from the interactive shell when possible. This is meant to keep AI-generated wrapper commands out of ordinary `bash_history` / zsh history; it is not a security boundary.

By default, `run.sh` and `send.sh` write local JSONL audit logs under `REMOTE_TMUX_LOG_DIR`. `run.sh` records the decoded command, start/end time, exit code, and captured output truncated to `REMOTE_TMUX_LOG_MAX_OUTPUT_LINES`; `send.sh` records that input was sent but cannot know the later exit code or output.

Each `run.sh` / `send.sh` invocation has a `request_id`. Scripts print `[request_id ...]`, and the same value is written to JSONL. Use `scripts/logs.sh last`, `scripts/logs.sh failures`, `scripts/logs.sh grep <pattern>`, `scripts/logs.sh show <request_id>`, or `scripts/logs.sh output <request_id>` to inspect local logs.

If sandbox blocks tmux socket access, rerun the read/send/run command with escalation.

Prefer the bundled scripts inside this skill directory so the workflow remains self-contained and portable.

## Operating Rules

- Start by reading the pane unless the user gave a precise command to run.
- Treat the tmux pane as shared state. The current prompt, cwd, active kubeconfig, and any running foreground command matter.
- Prefer `run.sh` for short, non-interactive inspection commands because it gives a scoped output and exit code.
- Prefer `send.sh` for commands expected to run for a long time, commands that intentionally change shell state such as `cd` or `export`, and commands with complex quoting.
- As a soft policy, prefer `run.sh` when command results need an audit trail, and prefer `send.sh` for changing directory, setting environment, starting long-running work, or handing control back to the user. This is guidance, not a hard restriction.
- The managed pane must not enter agent control while it is inside an interactive CLI, REPL, or TUI. If it is already in one, stop and ask the user to exit or handle it manually before continuing.
- Interactive CLIs and REPLs are not supported by this skill. Do not operate MySQL, Redis, Spark shell, psql, Python, Node, Oasis `work>`, or similar prompts by sending REPL input. Prefer one-shot non-interactive commands such as `mysql -e`, `redis-cli <command>`, `spark-sql -e`, `python -c`, or `node -e`, or use the dedicated skill that owns that CLI.
- Do not use this skill to exit a non-shell CLI. The dedicated skill must know how to leave its own prompt, because `exit`, `quit`, `bye`, and `\q` differ across CLIs and must be sent without shell wrapping.
- Bound unknown output. Do not dump unknown-size files, logs, or command results unless the user explicitly asks for full output.
- Prefer limited reads: `sed -n '1,120p' file`, `tail -n 100`, keyword/time filters, `journalctl -n --no-pager`, `docker logs --tail`, or `kubectl logs --tail`; check `ls -lh`/`wc` only when full content is needed.
- For complex multi-step checks, prefer a temporary script in non-production instead of fragile deeply nested one-liners; use `/tmp`, bounded output, and clean it up.
- Avoid full-screen TUI programs such as `vim`, `nano`, `less`, `top`, `htop`, and `watch`; use bounded non-interactive commands instead, or ask the user to handle the TUI and report when it is ready.
- When the pane is inside an inner interactive environment such as MySQL, Redis, Spark shell, psql, Python, Node, or a pod shell, do not use `run.sh` or `send.sh` for REPL commands. Use `read.sh` to report the state and ask the user to exit or handle the REPL manually.
- If `run.sh` refuses because it detected an interactive prompt, do not disable the detector; ask the user to exit or handle the REPL manually.
- For slow remote commands, wait and poll. Network, cold reads, package pulls, and K8s operations may be slow. Do not rush to `Ctrl-C`.
- Only send `Ctrl-C`, `pkill`, `kill`, `umount`, `helm upgrade`, `kubectl delete`, or similar disruptive commands when the user asks, clearly approves, or the terminal is unusable and recovery is necessary.
- Treat destructive or hard-to-reverse operations as requiring explicit confirmation. This includes `rm`, `rm -f`, `rm -rf`, deleting directories, deleting logs or result files, clearing caches, overwriting files with redirection, truncating files, moving data out of the way, restarting services, and cleaning test data. Before running one, briefly state the exact action and likely impact, then wait for the user to approve.
- In production, every command needs the chat approval flow above, even if it looks read-only. Do not rely on command prefixes to decide business risk.
- If a command opens a continuation prompt such as `>`, recover with `tmux send-keys -t "$REMOTE_TMUX_TARGET" C-c` only after confirming it is an accidental broken shell state.
- Never edit local repository code unless the user explicitly asks. This skill is for remote terminal operation.

## Disclaimer

Use this skill at your own risk. The user is solely responsible for reviewing commands, understanding their impact, and deciding whether to run them. The project authors and contributors are not responsible for outages, data loss, security incidents, business impact, incident response cost, or third-party claims arising from use or misuse of this tool.

## If The Remote Terminal Is Not Ready

If `read.sh` shows no usable remote shell, tmux has no configured pane, or the pane is not logged into the target machine, tell the user to start the terminal first. Ask them to:

- open or attach a tmux session named `remote`, or set `REMOTE_TMUX_TARGET` to the correct pane
- log into the target remote machine
- run any required setup there, such as `cd`, `export KUBECONFIG=...`, proxy settings, credentials, or environment activation

Then use `read.sh` again to verify the prompt and continue. Do not guess target hosts or credentials.

## Reporting

Summarize the important remote output in the final answer because the user may not see raw tool output. Include:

- The remote host, cwd, or context if visible.
- Whether the command completed, is still running, or was interrupted.
- Key metrics or errors.
- Any action taken that changed remote state.
