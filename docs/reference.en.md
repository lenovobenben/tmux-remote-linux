# tmux-remote-linux reference

This is the full English reference manual. For the Chinese version, see [reference.zh-CN.md](reference.zh-CN.md). For the short setup path, start with [../README.md](../README.md).

`tmux-remote-linux` is a small skill for AI coding tools. It operates a remote Linux shell through a local tmux pane that the user has already opened.

Some projects cannot be meaningfully validated from a developer laptop. The code is local, but the useful tests, diagnostics, and checks happen inside restricted remote environments: bastion hosts, MFA, jump scripts, shared machines, private kubeconfigs, internal datasets, or Kubernetes clusters that cannot be reached directly from the laptop.

This tool is useful for two common cases. The first is remote validation: the user has already completed SSH login, user switching, kubeconfig selection, environment setup, and other initialization, and the agent can run inspection, test, or post-deployment validation commands in that context. The second is production or remote incident diagnosis: the user controls access and sensitive input, while the agent reads state, runs bounded commands, analyzes logs, and summarizes findings inside an authorized terminal.

Codex does not need credentials and does not need to open its own SSH connection. The user logs in and prepares the shell; the agent only reads and writes the tmux pane.

The goal of this project is **reliable ordinary shell operation**, not full human-like terminal interactivity. It intentionally does not try to fully support high-interaction command-line programs or full-screen TUIs.

## Why This Tool Exists

Many production, internal, and bastion-hosted environments cannot be directly reached by a generic automation agent. The user often already has a terminal with the correct login state, network access, permissions, and context.

This project turns that terminal into a narrow operation channel:

- read recent pane output
- send one command
- run one short command and return only that command's output and exit code
- require an explicit production or non-production environment choice before use
- require human approval for every production command

The scripts are intentionally small. They do not manage SSH keys, bastion sessions, Kubernetes credentials, or server inventories.

## Repository Contents

- `scripts/read.sh`: read recent tmux pane output.
- `scripts/send.sh`: send one command and press Enter.
- `scripts/run.sh`: run one short command, use begin/end markers to capture only this command's output, and propagate the remote exit code.
- `scripts/env_guard.sh`: shared environment-selection and production-approval guard logic.
- `scripts/log.sh`: shared local JSONL audit logging helpers.
- `scripts/logs.sh`: query local JSONL audit logs.
- `SKILL.md`: safety and operating instructions for AI tools.

## Dependencies

Local machine requirements:

- macOS, Linux, or WSL on Windows
- `bash`
- `tmux`
- `base64`
- `awk`, `grep`, `sed`
- `jq` for `scripts/logs.sh` audit-log queries

macOS and Linux are the primary supported environments. On Windows, use WSL and install Codex, Claude Code, Gemini CLI, `tmux`, and this skill inside the same WSL distribution. Native Windows shells, PowerShell, and Git Bash are not primary test targets.

Remote pane requirements:

- an available shell prompt
- `bash` on the remote side for `run.sh`
- the user has already completed required remote initialization, such as login, directory selection, kubeconfig selection, and environment setup

### Install tmux

macOS with Homebrew:

```bash
brew install tmux
```

Debian / Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y tmux
```

RHEL / CentOS / Rocky Linux / AlmaLinux:

```bash
sudo yum install -y tmux
```

Systems using `dnf`:

```bash
sudo dnf install -y tmux
```

Confirm the installed version:

```bash
tmux -V
```

## Installation

Clone the repository anywhere:

```bash
git clone git@github.com:your-org-or-user/tmux-remote-linux.git /path/to/tmux-remote-linux
chmod +x /path/to/tmux-remote-linux/scripts/*.sh
```

The scripts can remain in the clone directory. AI tool integration differs by tool: Codex currently works best when `SKILL.md` and `scripts/` are installed into its skills directory; Claude Code, Gemini CLI, and similar tools can point a command file at this repository's `SKILL.md`.

### Codex

Codex needs `SKILL.md` and the scripts in its skills directory:

```bash
mkdir -p "$HOME/.codex/skills/tmux-remote-linux"
cp /path/to/tmux-remote-linux/SKILL.md "$HOME/.codex/skills/tmux-remote-linux/"
cp -R /path/to/tmux-remote-linux/scripts "$HOME/.codex/skills/tmux-remote-linux/"
chmod +x "$HOME/.codex/skills/tmux-remote-linux/scripts/"*.sh
```

Codex automatically loads skills under `~/.codex/skills/` on startup.

If you want an agent to use this skill at the right time, add a rule like this to the target project's `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, or your common prompt:

```text
If you are about to use ssh, use tmux-remote-linux instead. Even if ordinary SSH would work, the user should prepare a tmux pane first and the agent should operate that pane. Do not open a new SSH connection unless the user explicitly asks for direct SSH.
```

This rule is suitable for business projects because it tells the agent that `ssh` is the trigger. Whenever a task requires a remote shell, prefer the user-prepared tmux pane instead of trying direct SSH first.

### Claude Code

Create a `.md` command file under `~/.claude/commands/` that points to `SKILL.md`:

```bash
mkdir -p "$HOME/.claude/commands"
cat > "$HOME/.claude/commands/tmux-remote.md" << 'EOF'
Read and follow ~/.codex/skills/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
EOF
```

If you already installed the scripts for Codex, the command above can reuse that installation. If you did not install for Codex, point it at your clone path instead:

```bash
cat > "$HOME/.claude/commands/tmux-remote.md" << 'EOF'
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
EOF
```

Use `/tmux-remote` in Claude Code to trigger it.

### Gemini CLI

Create a `.toml` command file under `~/.gemini/commands/`:

```bash
mkdir -p "$HOME/.gemini/commands"
cat > "$HOME/.gemini/commands/tmux-remote.toml" << 'EOF'
description = "Read and write a remote Linux terminal through tmux"

prompt = """
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
"""
EOF
```

Use `/tmux-remote` in Gemini CLI to trigger it.

### Other Tools

The core logic is in `SKILL.md` and `scripts/`. If your AI tool supports custom commands or skills, a command that says "read and follow SKILL.md" is enough. The scripts do not need changes.

## Prepare tmux

Create or enter a local tmux session named `remote`:

```bash
tmux new -s remote
```

Common tmux commands:

```bash
tmux ls                         # list sessions
tmux new -s remote              # create and enter the remote session
tmux new -d -s remote           # create the remote session in the background
tmux attach -t remote           # re-enter the remote session
tmux switch -t remote           # switch to the remote session from inside tmux
tmux list-panes -a              # list all panes and targets
tmux kill-session -t remote     # close the remote session
tmux kill-server                # close the entire tmux server for the current user
```

`tmux kill-server` closes all tmux sessions for the current user. Use it only after confirming there are no important sessions.

Inside this tmux pane, the user logs in to the remote machine:

```bash
ssh your-bastion-or-host
ssh your-target-host
```

The scripts operate `remote:0.0` by default.

If your pane uses a different target, override it:

```bash
export REMOTE_TMUX_TARGET=remote:0.1
```

## Environment Selection Is Required

Before using any script, explicitly declare whether the target is production or non-production:

```bash
export REMOTE_TMUX_ENV=production
# or
export REMOTE_TMUX_ENV=non-production
```

This is mandatory. If `REMOTE_TMUX_ENV` is missing or invalid, all scripts refuse to continue.

### Production Mode

In production mode, every command sent through `send.sh` or `run.sh` pauses for local human approval.

The default is not to execute. In normal CLI use, the script displays a random digit from 0 to 9. The command is sent to the tmux pane only after the user enters that digit.

When Codex or another chat-style agent is using the skill, the agent should first show the target pane, the exact command, a Chinese explanation of what the command does, and a fresh random digit. Keep the approval prompt compact: put target and explanation on one line with visible `目标` and `说明` labels, put the command on its own line, and place the approval digit at the end of the approval sentence on that same command line. Use Markdown bold labels and inline code for highlighting. Do not use HTML tags or inline CSS, because some terminal renderers print them literally. The user only needs to reply with that digit to approve that one command. The agent can then pass the digit and explanation as one-time approval parameters to the script.

Normal CLI interactive confirmation prints an obvious warning with `!!!`. When a chat-style agent has already shown the production approval in chat, the script does not repeat those warnings. If a pane may affect real users, real data, online infrastructure, billing, security state, or any other production system, use production mode.

### Non-Production Mode

In non-production mode, `send.sh` and `run.sh` do not require production approval. Use this mode only for test, development, staging, temporary environments, or other targets where the risk is acceptable.

## Usage

Read the latest 40 lines of pane output:

```bash
scripts/read.sh
```

Read a specific number of lines:

```bash
scripts/read.sh 80
```

Send a command that changes shell state or starts a long-running shell command:

```bash
scripts/send.sh 'cd /var/log'
```

Run a short inspection command and return only this command's output:

```bash
scripts/run.sh 'pwd; hostname; date'
```

Example output:

```text
/root
remote-host
Thu Apr 30 10:30:00 UTC 2026

[exit 0]
```

If the remote command exits non-zero, `run.sh` prints `[exit N]`, and the local script exits with the same code.

## Overall Workflow

The core model is: the user prepares a local tmux pane and completes remote login, MFA, SSH jumps, user switching, kubeconfig selection, and other initialization inside it; the agent only reads and writes that pane through `read.sh`, `send.sh`, and `run.sh`. The scripts do not manage SSH connections, do not store credentials, do not know server inventories, and do not create separate remote sessions.

A typical operation usually looks like this:

1. The agent first uses `read.sh` to inspect the current pane.
2. It uses the prompt and output to identify the current host, user, directory, whether the pane is in a REPL, and whether a foreground command is running.
3. It chooses `run.sh` or `send.sh` based on the command type.
4. If the target is production, `send.sh` / `run.sh` requires human approval before sending the command.
5. After the command runs, the agent reads or captures output and summarizes key results.
6. If the command reaches a password, MFA, token, or other sensitive prompt, the agent stops sending input. The user completes the step directly in the tmux pane, then the agent reads the current state and continues.

### `read.sh`

`read.sh` only reads recent tmux pane output. It does not send any input to the remote side. It first checks `REMOTE_TMUX_ENV`, then reads the pane identified by `REMOTE_TMUX_TARGET`. By default, it filters obvious Codex wrapper and marker lines so transport details do not pollute normal context.

Use `read.sh` to confirm the current prompt, host, directory, foreground program state, or to poll a small amount of progress while a long command is running.

### `send.sh`

`send.sh` sends the command literally to the tmux pane and presses Enter once. It does not wrap the command, capture output, or know the remote exit code.

Use `send.sh` for commands that change the current interactive shell state, such as `cd`, `export`, or `sudo -i`; it is also suitable for long-running shell commands and follow-up operations after the user manually enters a password. Because it directly acts on the current pane, confirm the current prompt and context before sending.

By default, `send.sh` writes a local JSONL audit event with the request id, decoded command, target, environment, and send time. The event has `exit_code: null` and `output: null` because `send.sh` does not wait for command completion.

`send.sh` does not promise support for REPL-style interactive CLIs such as MySQL, Redis, Spark shell, psql, Python, or Node. Prefer one-shot non-interactive commands such as `mysql -e`, `redis-cli <command>`, `spark-sql -e`, `python -c`, or `node -e`. If the pane is already inside a REPL, the agent should report the state and ask the user to exit or handle it manually.

### `run.sh`

`run.sh` is for short, non-interactive inspection commands. It first checks configuration and current pane state, refuses to wrap commands on obvious interactive prompts such as MySQL, psql, Python, or Spark, and refuses to send a new command if it detects a previous `run.sh` begin marker without a corresponding end marker. This avoids stacking commands and polluting the pane.

After checks pass, `run.sh` generates unique begin/end markers, base64-encodes the user command locally, and sends a wrapper into the tmux pane. The wrapper prints the begin marker on the remote side and runs:

```bash
base64 -d | bash
```

It then records the remote exit code and prints the end marker and exit code. `run.sh` finds the begin/end markers in recent pane output, returns only this command's output, and prints `[exit N]`. The local script exits with the same code.

Commands are transferred through base64 to reduce issues with nested quotes, pipes, semicolons, and multiple shell-escaping layers. The command runs in a child remote `bash`, so `exit 7` only exits the child process and does not close the current interactive shell. It also means state changes such as `cd` and `export` do not persist after the command finishes.

By default, `run.sh` writes a local JSONL audit event with the request id, decoded command, target, environment, start time, end time, duration, exit code, and a truncated copy of the captured output. `run.sh` and `send.sh` also print `[request_id ...]` locally so terminal output can be matched back to JSONL later.

### Remote History Noise Reduction

By default, commands sent to tmux are prefixed with shell history settings and a leading space. For bash, the wrapper sets `HISTCONTROL=ignoreboth:erasedups`; for zsh, it attempts `setopt HIST_IGNORE_SPACE`. After the sent command completes, the wrapper also tries to delete the just-sent history entry from the interactive shell. `run.sh` additionally executes its transport wrapper inside a child `bash` with `HISTFILE=/dev/null`.

This is meant to keep long AI-generated wrapper commands out of ordinary interactive shell history, especially base64 transport lines and failed retries. It is not a security boundary and does not attempt to bypass terminal recording, bastion auditing, system audit logs, or provider session logs.

### State Boundaries

The tmux pane is shared mutable state, not an isolated sandbox. `send.sh` changes the current interactive shell; `run.sh` starts a child `bash` based on the current directory and environment; user input, foreground programs, REPLs, SSH jumps, container shells, and kubeconfig all affect the meaning of later commands. Full-screen TUI programs such as `vim`, `nano`, `less`, `top`, `htop`, and `watch` are not linear text protocols. Agents cannot reliably understand mode, cursor position, scrolling, save state, and exit behavior, so they should avoid operating them.

Therefore, the agent should confirm pane state before continuing; unknown-size output should be read with limits; sensitive input should be entered by the user manually; and production commands should be approved one by one. This project provides a narrow terminal transport channel, not a permission system or a remote state manager.

## Configuration

```bash
REMOTE_TMUX_TARGET=remote:0.0
REMOTE_TMUX_ENV=non-production
REMOTE_TMUX_LINES=40
REMOTE_TMUX_FILTER_WRAPPER=1
REMOTE_TMUX_RUN_WAIT_SECONDS=1
REMOTE_TMUX_RUN_CAPTURE_LINES=400
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
REMOTE_TMUX_COMMAND_EXPLANATION='Explain what this production command will do'
REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT=7
REMOTE_TMUX_PROD_APPROVAL_DIGIT=7
```

### `REMOTE_TMUX_TARGET`

The tmux pane to operate. Default: `remote:0.0`.

### `REMOTE_TMUX_ENV`

Required. Allowed values:

- `production`
- `non-production`

### `REMOTE_TMUX_LINES`

Default number of lines for `read.sh` to read. Default: `40`.

### `REMOTE_TMUX_FILTER_WRAPPER`

Whether `read.sh` filters obvious Codex wrapper and marker lines. Default: `1`. The filter is conservative: it hides `__CODEX_RUN_...` markers, and it hides wrapper command lines only when a single line contains `__CODEX_RUN_...`, `base64 -d | bash`, and `__codex_status`. This avoids hiding ordinary base64 output by mistake. Set it to `0` when debugging transport-layer behavior.

### `REMOTE_TMUX_RUN_WAIT_SECONDS`

How long `run.sh` waits after sending the command before capturing output. Default: `1` second.

### `REMOTE_TMUX_RUN_CAPTURE_LINES`

How many pane lines `run.sh` captures while searching for begin/end markers. Default: `400`.

### `REMOTE_TMUX_RUN_MAX_OUTPUT_LINES`

Maximum number of lines `run.sh` prints from this command's output. Default: `200`.

### `REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES`

Maximum number of bytes `run.sh` prints from this command's output. Default: `32768`.

### `REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES`

If `run.sh` finds the begin marker but not the end marker, it prints at most this many recent lines after the begin marker. Default: `40`.

### `REMOTE_TMUX_DETECT_INTERACTIVE`

When set to `1`, `run.sh` refuses to execute if the pane appears to be inside a child interactive CLI such as MySQL, psql, Python, Spark shell, redis-cli, mongo shell, or sqlite. Default: `1`.

### `REMOTE_TMUX_AVOID_REMOTE_HISTORY`

When set to `1`, `send.sh` and `run.sh` prefix sent commands with history-ignore settings and a leading space, then try to delete the just-sent history entry from the interactive shell. This reduces pollution in the remote interactive shell history. Default: `1`.

### `REMOTE_TMUX_LOG_ENABLED`

Whether `send.sh` and `run.sh` write local JSONL audit logs. Default: `1`. Set to `0` to disable local audit logging.

### `REMOTE_TMUX_LOG_DIR`

Local directory for audit logs. Default: `$HOME/.codex/tmux-remote-linux/logs`. Logs are written as one JSONL file per local day, for example `2026-05-17.jsonl`.

### `REMOTE_TMUX_LOG_MAX_OUTPUT_LINES`

Maximum number of command output lines stored in each `run.sh` audit event. Default: `10`. This does not affect how many lines `run.sh` prints to the caller; that is controlled by `REMOTE_TMUX_RUN_MAX_OUTPUT_LINES`.

### `REMOTE_TMUX_LOG_RETENTION_DAYS`

How long local `*.jsonl` audit log files are retained. Default: `7`. Cleanup runs opportunistically when a new log event is written.

### `REMOTE_TMUX_REQUEST_ID`

Optional request id to use for a single `run.sh` or `send.sh` invocation. If unset, the scripts generate an id from local time and process id. This id is printed by the script and written into JSONL so terminal output, chat context, and local logs can be correlated.

### `REMOTE_TMUX_COMMAND_EXPLANATION`

Optional for non-production. Required for non-interactive production approval. This should explain in user-friendly language what the command will do and why it is needed.

### `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT`

Production approval parameter for chat-style agents. This is the random digit shown to the user before execution.

### `REMOTE_TMUX_PROD_APPROVAL_DIGIT`

Production approval parameter for chat-style agents. This is the digit the user replied with. The script accepts non-interactive production execution only when this matches `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT` and `REMOTE_TMUX_COMMAND_EXPLANATION` is provided.

## Token Use

Operating a remote terminal through tmux usually uses slightly more tokens than working directly in a local repository. The agent needs to repeatedly read terminal context, confirm the current prompt, filter wrapper output, and summarize remote command results. Remote commands that print large logs, tables, or pane history also directly increase context and response usage.

Suggestions to reduce token use:

- Prefer `run.sh` for short, clear inspection commands so the script returns only this command's output.
- Avoid printing large logs directly; first narrow results with `tail -n`, `head -n`, `grep`, `awk`, `sed`, `jq`, and similar tools.
- Specify a smaller line count when reading the pane, for example `scripts/read.sh 20`; do not habitually read hundreds of lines.
- For `kubectl get`, log queries, and database queries, prefer namespace, label, time range, field selection, or limit options.
- For long-running tasks, wait and poll small amounts of output instead of frequently capturing large chunks.

Configuration values that affect token use:

```bash
REMOTE_TMUX_LINES=40                    # default read.sh line count
REMOTE_TMUX_RUN_CAPTURE_LINES=400       # pane lines captured by run.sh while searching markers
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200    # maximum output lines printed by run.sh
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768  # maximum output bytes printed by run.sh
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40 # maximum tail lines while a command is still running
REMOTE_TMUX_FILTER_WRAPPER=1            # filter obvious wrapper and marker lines
REMOTE_TMUX_LOG_MAX_OUTPUT_LINES=10     # maximum output lines stored in local audit logs
```

For daily inspection, you can reduce `REMOTE_TMUX_LINES`, `REMOTE_TMUX_RUN_MAX_OUTPUT_LINES`, and `REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES`. Temporarily increase them only while diagnosing complex issues, so unrelated history does not enter the agent context.

## When To Use `send.sh` vs `run.sh`

Short, non-interactive inspection commands are suitable for `run.sh`:

```bash
scripts/run.sh 'systemctl status nginx --no-pager'
scripts/run.sh 'kubectl get pods -n default'
scripts/run.sh 'df -h'
```

Commands that change shell state or keep running are suitable for `send.sh`:

```bash
scripts/send.sh 'cd /opt/app'
scripts/send.sh 'sudo -i'
scripts/send.sh 'tail -f /var/log/app.log'
```

`run.sh` executes commands in a child remote `bash` process. Therefore `cd`, `export`, and similar shell state changes do not persist after the command exits. Use `send.sh` when state must persist.

As a soft audit policy, prefer `run.sh` when command results need to be recorded, and prefer `send.sh` for changing directory, setting environment, starting long-running work, or handing control back to the user. This is guidance, not a hard restriction.

Agents do not operate REPL-style interactive CLIs through this skill. Typical examples include `mysql>`, `redis-cli`, `psql>`, `spark-shell>`, Python REPL, Node REPL, attached container shells, or any prompt where state lives inside the current interactive program. Use non-interactive commands instead, such as `mysql -e`, `redis-cli <command>`, `spark-sql -e`, `python -c`, or `node -e`. If the pane is already inside a REPL, the user should exit or handle it manually before the agent continues.

Complex multi-step checks, especially checks that span multiple hosts and include loops, regular expressions, pipes, or nested `ssh`, should not be forced into a very long one-line shell command. Multi-layer quoting passes through the local shell, `run.sh`, the remote shell, a child `bash`, and inner `ssh`, which makes syntax errors likely.

In non-production environments, a more reliable approach is to write a temporary script under `/tmp`, express the logic as normal multi-line shell, bound the output, execute it, and clean it up. For example:

```bash
tmp="/tmp/tmux-remote-linux-check-$$.sh"
cat > "$tmp" <<'EOF'
#!/usr/bin/env bash
set -u
for h in master1 master2 master3; do
  echo "===== $h ====="
  ssh "$h" hostname
  ssh "$h" "ss -lntp | grep 9092 | head -n 5"
done
EOF
bash "$tmp"
rm -f "$tmp"
```

Do not write temporary scripts by default in production. Consider doing so only when the user explicitly approves and the script contents, path, and impact are clear.

## How `run.sh` Works

`run.sh`:

1. Generates unique begin/end markers.
2. Base64-encodes the command locally.
3. Sends a small wrapper into the tmux pane.
4. Decodes the command remotely and runs it with `bash`.
5. Captures recent pane output.
6. Prints only content between the begin/end markers, subject to line and byte limits.
7. Prints `[exit N]` and exits locally with the same code.

This avoids most nested-quote issues and prevents commands like `exit 7` from closing the current remote shell.

If the begin marker is not found, `run.sh` does not print old pane history. If the begin marker is found but the end marker is not found yet, it prints only a short tail of this command's output and exits with `124`.

## Notes

- **Reliability first, not full interactivity.** This skill is suitable for ordinary shell commands, short checks, bounded output, long-task startup, and state confirmation. It is not suitable for making an agent operate complex interactive command-line programs like a human.
- **Do not hand the pane to an agent while it is inside an interactive command-line program.** Before handing the pane to an agent, exit MySQL, Redis, psql, Spark shell, Python REPL, Node REPL, container interactive shells, `vim`, `less`, `top`, `watch`, and similar states. Return to a clear ordinary shell prompt.
- **Treat the tmux pane used by the agent as an agent-managed terminal.** Avoid manually typing commands into the same pane while the agent is using it. Manual operations change cwd, user, host, environment variables, kubeconfig, REPL state, and output boundaries, and can cause the agent to misread context or attribute output to the wrong command.
- **Best practice: keep the managed tmux session invisible by default.** After the remote shell is ready, detach the tmux session with `Ctrl-b d` and let the agent operate it in the background. Reattach with `tmux attach -t remote` only when you need to enter a password, MFA, token, or intentionally take over; detach again when finished. Do not leave the agent-managed pane open in a normal terminal window for a long time, because it may be accidentally reused for other production or test work.
- `REMOTE_TMUX_ENV` controls only the script's confirmation policy. It does not detect whether the current remote target is actually test or production. If the user manually changes the managed pane from a test machine to a production machine, the agent may continue under the old assumption. Therefore the managed pane should not be used as a daily manual operations terminal.
- If manual work is needed, use another terminal, another tmux pane, or another tmux session. If you want the agent to understand and continue later, it is usually better to ask the agent to run the command.
- If you manually changed the managed pane, tell the agent what you did, which host it is on, which user, which directory, whether it entered a container or REPL, and then let it continue.
- **Sensitive input is user-owned.** Do not paste SSH passwords, database passwords, `sudo` passwords, MFA codes, API tokens, private keys, or other credentials into the agent chat.
- If a command reaches a password, MFA, or other sensitive prompt, the agent should stop sending input and let the user type directly in the tmux pane. After completing it, the user only needs to say "input complete", "login succeeded", or "continue". The agent should then reread the pane and confirm the current prompt, host, user, directory, and context before continuing.
- Avoid letting the agent operate full-screen TUIs such as `vim`, `nano`, `less`, `top`, `htop`, and `watch`. Prefer `sed -n`, `head`, `tail`, and `grep` for file viewing; prefer `grep`, `rg`, and `find` for searching. For complex file edits, the user should edit manually and tell the agent to continue checking.
- Treat the tmux pane as shared mutable state.
- Before any operation, confirm the current prompt, host, user, directory, kubeconfig, and shell context.
- Beware stale panes. The host shown in the pane may no longer be the host you think it is.
- Beware aliases, shell functions, environment variables, and virtual environments.
- In production, do not type or reply with the approval digit if you do not understand the command and its impact.
- Every production command should be approved separately. Do not judge risk only by the command prefix; shell context, kubeconfig, aliases, environment variables, and business logic can change the actual impact.
- Use `send.sh` for state-changing or long-running shell commands, and `run.sh` for bounded inspection commands. REPL-style interactive CLIs are not operated by the agent.
- Avoid multi-line production operations through this tool. Complex procedures should be performed by the user directly in the terminal.
- Do not treat this project as a permission system. It is a local safety guard, not a security boundary.

High-risk commands require extra care, including but not limited to:

- `rm`, `mv`, `chmod -R`, `chown -R`
- `dd`, `mkfs`, partition changes, mount changes
- `systemctl restart`, `systemctl stop`
- `kubectl delete`, `kubectl apply`, `kubectl scale`
- `helm upgrade`, `helm uninstall`
- `terraform apply`, `terraform destroy`
- firewall, routing, reboot, shutdown, database migration, and data deletion commands

## Audit Logs

`send.sh` and `run.sh` write local append-only JSONL audit logs by default. The default directory is:

```bash
$HOME/.codex/tmux-remote-linux/logs
```

Files are split by local date:

```text
2026-05-17.jsonl
```

`run.sh` records the request id, decoded command, target pane, environment, start time, end time, duration, exit code, and captured output truncated to `REMOTE_TMUX_LOG_MAX_OUTPUT_LINES`. `send.sh` records the request id, decoded command, target pane, environment, and send time, but uses `exit_code: null` and `output: null` because it does not wait for completion.

Use `scripts/logs.sh` to query logs:

```bash
scripts/logs.sh path
scripts/logs.sh last 10
scripts/logs.sh today 20
scripts/logs.sh failures
scripts/logs.sh grep df
scripts/logs.sh show 20260517-172200-12345
scripts/logs.sh output 20260517-172200-12345
```

`logs.sh` requires local `jq`.

Audit logs are local sensitive files. They may contain production commands, host names, business output, or error details. User-entered passwords, MFA codes, and secrets typed directly into the pane are not captured by these scripts, but command text and output may still contain sensitive data.

Old `*.jsonl` files are deleted after `REMOTE_TMUX_LOG_RETENTION_DAYS` days. Cleanup is opportunistic and runs when a new log event is written.

## FAQ

### `REMOTE_TMUX_ENV is required`

Set the environment explicitly:

```bash
export REMOTE_TMUX_ENV=non-production
```

or:

```bash
export REMOTE_TMUX_ENV=production
```

### `error connecting to ... tmux`

Confirm tmux is running and the target pane exists:

```bash
tmux list-sessions
tmux list-panes -a
```

Set `REMOTE_TMUX_TARGET` if needed.

### `begin marker not found yet`

`run.sh` did not see the begin marker for its wrapper in the captured pane output. It intentionally avoids printing old pane history. Inspect the current pane directly:

```bash
scripts/read.sh 40
```

### `end marker not found yet`

The command may still be running, or the capture window may be too small. You can increase:

```bash
export REMOTE_TMUX_RUN_CAPTURE_LINES=1000
```

Then inspect the pane:

```bash
scripts/read.sh 200
```

### `interactive prompt detected`

The pane appears to be inside a child interactive CLI such as MySQL, psql, Python, Spark shell, redis-cli, mongo shell, or sqlite. The agent should not continue sending REPL input. Ask the user to exit or handle that REPL manually, or use a non-interactive command such as `mysql -e`, `redis-cli <command>`, `spark-sql -e`, `python -c`, or `node -e`.

### `cd` or `export` in `run.sh` did not persist

This is expected. Use `send.sh` when you need to change remote shell state:

```bash
scripts/send.sh 'cd /opt/app'
```

## Disclaimer

Use this project at your own risk. Remote terminal automation can cause service outages, data loss, security incidents, irreversible operations damage, financial loss, or business interruption, especially in production environments.

You are responsible for reviewing commands, understanding impact, confirming the target environment, and deciding whether to execute. The project authors and contributors are not liable for any damage, loss, downtime, incident response cost, business impact, security incident, data loss, or third-party claim caused by use or misuse of this tool.
