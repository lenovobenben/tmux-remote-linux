# tmux-remote-linux

`tmux-remote-linux` lets Codex, Claude Code, Gemini CLI, or another AI coding tool operate a remote Linux shell through a local `tmux` pane that you already control.

It is useful when you have already logged in through SSH, a bastion host, MFA, VPN, root switching, or a prepared kubeconfig. The AI tool does not need your credentials and does not open its own remote connection. It only reads and writes the tmux pane you point it at.

For the full manual, configuration reference, and troubleshooting notes, see [docs/reference.md](docs/reference.md).

## Platform Notes

macOS and Linux are the primary supported environments. On Windows, use WSL and install Codex, Claude Code, Gemini CLI, `tmux`, and this skill inside the same WSL distribution.

## Quick Start

If `tmux` is not installed yet, install it with your normal package manager first, for example `brew install tmux`, `sudo apt-get install tmux`, `sudo yum install tmux`, or `sudo dnf install tmux`.

Create a local tmux session named `remote`:

```bash
tmux new -s remote
```

Inside that tmux window, log in to the remote machine yourself:

```bash
ssh your-bastion-or-host
ssh your-target-host
```

Leave that tmux pane open. By default, this skill operates `remote:0.0`.

## Install For Your AI Tool

### Codex

Copy this skill into Codex's skills directory:

```bash
mkdir -p "$HOME/.codex/skills/tmux-remote-linux"
cp SKILL.md "$HOME/.codex/skills/tmux-remote-linux/"
cp -R scripts "$HOME/.codex/skills/tmux-remote-linux/"
chmod +x "$HOME/.codex/skills/tmux-remote-linux/scripts/"*.sh
```

Then ask Codex something like:

```text
使用 tmux-remote-linux。目标是 remote:0.0，环境是 non-production。请先读取当前 pane。
```

### Claude Code

Create a command that points Claude Code to this skill:

```bash
mkdir -p "$HOME/.claude/commands"
cat > "$HOME/.claude/commands/tmux-remote.md" << 'EOF'
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
EOF
```

Replace `/path/to/tmux-remote-linux` with this repository's path. Then use `/tmux-remote` in Claude Code.

### Gemini CLI

Create a command that points Gemini CLI to this skill:

```bash
mkdir -p "$HOME/.gemini/commands"
cat > "$HOME/.gemini/commands/tmux-remote.toml" << 'EOF'
description = "Read and write a remote Linux terminal through tmux"

prompt = """
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
"""
EOF
```

Replace `/path/to/tmux-remote-linux` with this repository's path. Then use `/tmux-remote` in Gemini CLI.

## Daily Use

Most users only need to remember three things:

- Default target: `remote:0.0`
- You must choose an environment: `production` or `non-production`
- Short checks use `run.sh`; interactive input, `cd`, `export`, and long-running commands use `send.sh`

**Treat the target tmux pane as agent-managed.** Avoid typing your own commands into the same pane while the AI is using it. If you need manual work, open another terminal, pane, or session, or ask the agent to run the command. If you did change the managed pane manually, tell the agent what changed before asking it to continue.

**Best practice: detach the managed tmux session.** After the remote shell is ready, detach with `Ctrl-b d` and let the agent operate it in the background. Re-attach with `tmux attach -t remote` only when you need to type a secret or intentionally take over, then detach again.

**Sensitive prompts are user-owned.** Do not paste passwords, MFA codes, tokens, private keys, or other secrets into the AI chat. If a command asks for a secret, type it directly in the tmux pane, then tell the agent that the step is complete.

Useful tmux commands:

```bash
tmux ls                     # list sessions
tmux new -s remote          # create and enter a session
tmux attach -t remote       # re-enter a session
tmux list-panes -a          # find pane targets
tmux kill-session -t remote # close the remote session
```

If your pane is not `remote:0.0`, tell the AI the correct target, for example `remote:0.1`.

## Production Use

In production, every command must be approved by you before it is sent to tmux. The AI should show the target, environment, exact command, and a one-digit approval challenge. Only reply with that digit if you understand and approve that exact command.

Do not allow an AI tool to set production approval environment variables by itself. They are only a relay of your explicit approval.

## Token Usage

Using a remote tmux pane can use slightly more tokens than local coding because the AI needs to read terminal context and summarize remote output. For normal use, you usually do not need to tune anything.

If output gets large, ask the AI to read fewer pane lines, use `tail -n`, narrow logs with `grep`, or reduce these settings:

```bash
REMOTE_TMUX_LINES=20
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=80
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=20
```

See [docs/reference.md](docs/reference.md) for all settings and edge cases.
