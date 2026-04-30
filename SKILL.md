---
name: tmux-remote-linux
description: Use this when the user wants Codex to operate a remote Linux terminal through the bundled tmux wrapper scripts in this skill. The skill provides a generic remote command read/write interface for shell, ssh, kubectl, helm, logs, and diagnostics while preserving terminal state and waiting patiently for slow remote commands.
metadata:
  short-description: Read and write a remote Linux terminal through tmux
---

# tmux Remote Linux

Use the user's tmux bridge when the task is about operating a remote Linux terminal that the user has opened locally. This skill is a generic terminal transport: read remote output, send commands, and report results.

## Interface

The scripts default to tmux target `remote:0.0`. Override it with `REMOTE_TMUX_TARGET` when the user has multiple remote panes.

Before any script use, the user must explicitly choose the target environment:

```bash
export REMOTE_TMUX_ENV=production
# or
export REMOTE_TMUX_ENV=non-production
```

Do not infer this value. Ask the user if it is not already set or explicitly provided. In `production` mode, every command sent through `send.sh` or `run.sh` must stop for explicit user confirmation. Interactive CLI confirmation shows a warning with `!!!`; chat-approved commands stay quiet because the chat prompt already showed the production approval. In `non-production` mode, commands may run without production confirmation.

Production warning policy: when the user selects `production`, remind them to be extremely careful with AI-assisted remote operations. AI can misunderstand shell context, stale panes, aliases, credentials, kubeconfigs, current directories, and blast radius. Make clear that the user is responsible for each command they approve.

Production chat approval policy for Codex:

1. Before every production `send.sh` or `run.sh` command, generate a fresh random digit from `0` to `9`.
2. Show the user the target, environment, exact command, and a clear Chinese explanation of what the command will do and why it is needed.
3. Keep the approval prompt compact. Do not add blank lines between the explanation, target/environment, command, and approval digit. Put target and environment on one line. Put the command on the next line. Put the approval digit at the end of the approval sentence. Use only Markdown styles that render reliably in Codex terminal output: bold labels and inline-code values. Do not use HTML tags or inline CSS; they may be printed literally.
4. Use this rendered Markdown format, not a fenced code block:
   **生产确认**：**目标** `remote:0.0`，**环境** `production`。**说明**：`<one concise Chinese sentence>`。
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

- Run one command with begin/end markers and an exit-code line:

```bash
$HOME/.codex/skills/tmux-remote-linux/scripts/run.sh '<command>'
```

`run.sh` sends the command through base64, executes it in a remote `bash` child process, waits briefly, captures recent pane output, and prints only the output between its unique markers. It appends `[exit N]` when the end marker is visible, and the local script exits with the remote command's exit code. It does not dump old pane history if its begin marker is missing. For long-running commands, if the end marker is not visible yet, wait and call `read.sh` to inspect progress rather than interrupting.

Important: `run.sh` always starts a fresh non-interactive `bash` child. Do not use it to query or control state that only exists inside the current interactive program, such as `mysql>`, `spark-shell>`, `psql>`, a Python REPL, an attached container shell, or shell in-memory history. Use `read.sh` to identify the current prompt, then use `send.sh` for the exact REPL input.

Useful optional environment variables:

```bash
REMOTE_TMUX_TARGET=remote:0.0
REMOTE_TMUX_ENV=non-production
REMOTE_TMUX_FILTER_WRAPPER=1
REMOTE_TMUX_RUN_WAIT_SECONDS=1
REMOTE_TMUX_RUN_CAPTURE_LINES=400
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40
REMOTE_TMUX_DETECT_INTERACTIVE=1
```

If sandbox blocks tmux socket access, rerun the read/send/run command with escalation.

Prefer the bundled scripts inside this skill directory so the workflow remains self-contained and portable.

## Operating Rules

- Start by reading the pane unless the user gave a precise command to run.
- Treat the tmux pane as shared state. The current prompt, cwd, active kubeconfig, and any running foreground command matter.
- Prefer `run.sh` for short, non-interactive inspection commands because it gives a scoped output and exit code.
- Prefer `send.sh` for interactive programs, commands expected to run for a long time, commands that intentionally change shell state such as `cd` or `export`, and commands with complex quoting.
- When the pane is inside an inner interactive environment such as MySQL, Spark shell, psql, Python, a pod shell, or an SSH session waiting at a prompt, do not wrap the next command with `run.sh`. Send one REPL command with `send.sh`, then poll with `read.sh`. For MySQL, prefer `\g` as the statement terminator or ensure `send.sh` sends the text literally before pressing Enter.
- If `run.sh` refuses because it detected an interactive prompt, use `send.sh`; do not disable the detector unless the user explicitly asks.
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
