#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/env_guard.sh
source "$script_dir/env_guard.sh"
remote_tmux_require_environment

target="${REMOTE_TMUX_TARGET:-remote:0.0}"
lines="${1:-${REMOTE_TMUX_LINES:-40}}"
filter_wrapper="${REMOTE_TMUX_FILTER_WRAPPER:-1}"

if ! [[ "$lines" =~ ^[0-9]+$ ]] || [ "$lines" -le 0 ]; then
  echo "usage: $0 [positive-line-count]" >&2
  exit 2
fi

if [ "$filter_wrapper" = "0" ]; then
  tmux capture-pane -t "$target" -p -S "-$lines"
else
  tmux capture-pane -J -t "$target" -p -S "-$lines" | awk '
    /__CODEX_RUN_[0-9]+_[0-9]+_(BEGIN|END)__(:[0-9]+)?/ { next }
    /__TRL_COUNTER/ && /PROMPT_COMMAND=/ { next }
    /__trl_status/ && /31D763DA06_TRL/ { next }
    {
      gsub(/__31D763DA06_TRL_[0-9]+_[0-9]+__ ?/, "")
    }
    /__CODEX_RUN_[0-9]+_[0-9]+/ && /base64 -d[[:space:]]*\|[[:space:]]*bash/ && /__codex_status/ { next }
    /__tmux_remote_hist_id/ && /HISTTIMEFORMAT= history/ { next }
    /export HISTCONTROL=ignoreboth:erasedups/ && /base64 -d[[:space:]]*\|[[:space:]]*HISTFILE=\/dev\/null/ { next }
    /base64 -d[[:space:]]*\|[[:space:]]*HISTFILE=\/dev\/null/ { next }
    /export HISTCONTROL=ignoreboth:erasedups; setopt HIST_IGNORE_SPACE 2>\/dev\/null \|\| true; / {
      sub(/export HISTCONTROL=ignoreboth:erasedups; setopt HIST_IGNORE_SPACE 2>\/dev\/null \|\| true; /, "")
      sub(/; __tmux_remote_hist_id=\$\(HISTTIMEFORMAT= history 1 2>\/dev\/null \| awk '\''\{print \$1\}'\''\); \[ -n "\$__tmux_remote_hist_id" \] && history -d "\$__tmux_remote_hist_id" 2>\/dev\/null \|\| true; unset __tmux_remote_hist_id/, "")
    }
    { print }
  '
fi
