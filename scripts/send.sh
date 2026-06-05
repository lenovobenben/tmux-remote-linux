#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/env_guard.sh
source "$script_dir/env_guard.sh"
# shellcheck source=scripts/log.sh
source "$script_dir/log.sh"
remote_tmux_require_environment

target="${REMOTE_TMUX_TARGET:-remote:0.0}"
avoid_remote_history="${REMOTE_TMUX_AVOID_REMOTE_HISTORY:-1}"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 '<command>'" >&2
  exit 2
fi

recent_prompt="$(tmux capture-pane -J -t "$target" -p -S -20)"
if printf "%s\n" "$recent_prompt" | grep -Eq '(^|[[:space:]])(work>|mysql>|MariaDB \[[^]]+\]>|postgres[=#]|[^[:space:]]+=>|redis[^>]*>|>>>|\.\.\.|In \[[0-9]+\]:|spark-sql>|scala>|psql[^>]*>) ?$'; then
  echo "interactive non-shell prompt detected; send.sh only sends shell commands" >&2
  echo "Use the owner skill for this CLI, for example oasis-cli/scripts/oasis_exit.sh for Oasis work>." >&2
  exit 2
fi

remote_tmux_confirm_if_production "$1"
request_id="$(remote_tmux_log_request_id)"
if [ "$avoid_remote_history" = "0" ]; then
  tmux send-keys -t "$target" -l -- "$1"
else
  tmux send-keys -t "$target" -l -- " export HISTCONTROL=ignoreboth:erasedups; setopt HIST_IGNORE_SPACE 2>/dev/null || true; $1; __tmux_remote_hist_id=\$(HISTTIMEFORMAT= history 1 2>/dev/null | awk '{print \$1}'); [ -n \"\$__tmux_remote_hist_id\" ] && history -d \"\$__tmux_remote_hist_id\" 2>/dev/null || true; unset __tmux_remote_hist_id"
fi
tmux send-keys -t "$target" Enter
remote_tmux_log_send_event "send.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$1" "$(remote_tmux_log_now)"
echo "[request_id $request_id]"
