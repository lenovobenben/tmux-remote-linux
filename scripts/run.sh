#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/env_guard.sh
source "$script_dir/env_guard.sh"
remote_tmux_require_environment

target="${REMOTE_TMUX_TARGET:-remote:0.0}"
wait_seconds="${REMOTE_TMUX_RUN_WAIT_SECONDS:-1}"
capture_lines="${REMOTE_TMUX_RUN_CAPTURE_LINES:-400}"
max_output_lines="${REMOTE_TMUX_RUN_MAX_OUTPUT_LINES:-200}"
max_output_bytes="${REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES:-32768}"
pending_output_lines="${REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES:-40}"
detect_interactive="${REMOTE_TMUX_DETECT_INTERACTIVE:-1}"

if [ "$#" -lt 1 ]; then
  echo "usage: $0 '<command>'" >&2
  exit 2
fi

for numeric_value in "$wait_seconds" "$capture_lines" "$max_output_lines" "$max_output_bytes" "$pending_output_lines"; do
  if ! [[ "$numeric_value" =~ ^[0-9]+$ ]]; then
    echo "run.sh configuration values must be non-negative integers" >&2
    exit 2
  fi
done

if [ "$capture_lines" -le 0 ] || [ "$max_output_lines" -le 0 ] || [ "$max_output_bytes" -le 0 ] || [ "$pending_output_lines" -le 0 ]; then
  echo "run.sh line and byte limits must be positive" >&2
  exit 2
fi

limit_output() {
  awk -v max_lines="$max_output_lines" -v max_bytes="$max_output_bytes" '
    BEGIN { used = 0 }
    {
      line_bytes = length($0) + 1
      if (NR > max_lines || used + line_bytes > max_bytes) {
        truncated = 1
        exit
      }
      print
      used += line_bytes
    }
    END {
      if (truncated) {
        printf("[run.sh] output truncated: set REMOTE_TMUX_RUN_MAX_OUTPUT_LINES or REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES to expand\n") > "/dev/stderr"
      }
    }
  '
}

detect_interactive_prompt() {
  local recent last_line

  recent="$(tmux capture-pane -t "$target" -p -S -10)"
  last_line="$(printf '%s\n' "$recent" | awk 'NF { line = $0 } END { print line }')"
  last_line="${last_line%$'\r'}"

  case "$last_line" in
    *"mysql> "*|*"mysql>"|*"MariaDB ["*"]> "*|*"MariaDB ["*"]>"|*"postgres=# "*|*"postgres=#"|*"postgres=> "*|*"postgres=>"|*"sqlite> "*|*"sqlite>"|*"redis"*"> "*|*"redis"*">"|*"mongo> "*|*"mongo>"|*">>> "*|*">>>"|*"... "*|*"..."|*"scala> "*|*"scala>"|*"spark-sql> "*|*"spark-sql>")
      cat >&2 <<EOF
[run.sh] interactive prompt detected; refusing to wrap input in a child bash.
[run.sh] last prompt: ${last_line}
[run.sh] Use send.sh for the REPL input, then read.sh to inspect the result.
EOF
      exit 5
      ;;
  esac
}

command_text="$1"

if [ "$detect_interactive" != "0" ]; then
  detect_interactive_prompt
fi

remote_tmux_confirm_if_production "$command_text"

marker="CODEX_RUN_$(date +%s)_$$"
begin="__${marker}_BEGIN__"
end="__${marker}_END__"

encoded_command="$(printf '%s' "$command_text" | base64 | tr -d '\n')"
remote_command="printf '\n%s\n' '$begin'; printf '%s' '$encoded_command' | base64 -d | bash; __codex_status=\$?; printf '\n%s:%s\n' '$end' \"\$__codex_status\""

tmux send-keys -t "$target" -l -- "$remote_command"
tmux send-keys -t "$target" Enter
sleep "$wait_seconds"

captured="$(tmux capture-pane -t "$target" -p -S "-$capture_lines")"

if ! printf '%s\n' "$captured" | grep -Fxq "$begin"; then
  echo "[run.sh] begin marker not found yet: $begin" >&2
  echo "[run.sh] not printing pane history; use read.sh 40 if you need to inspect the current pane" >&2
  exit 124
fi

if ! printf '%s\n' "$captured" | grep -q "^${end}:"; then
  printf '%s\n' "$captured" | awk -v begin="$begin" -v max_lines="$pending_output_lines" '
    $0 == begin { seen = 1; next }
    seen {
      lines[++count] = $0
    }
    END {
      start = count - max_lines + 1
      if (start < 1) {
        start = 1
      }
      for (i = start; i <= count; i++) {
        print lines[i]
      }
    }
  ' | limit_output
  echo "[run.sh] end marker not found yet; command may still be running" >&2
  exit 124
fi

printf '%s\n' "$captured" | awk -v begin="$begin" -v end="$end" '
  $0 == begin { seen = 1; next }
  seen && index($0, end ":") == 1 {
    done = 1
    exit
  }
  seen { print }
  END {
    if (seen && !done) {
      print "[run.sh] end marker not found yet" > "/dev/stderr"
      exit 124
    }
    if (!seen) {
      exit 124
    }
  }
' | limit_output

remote_status="$(printf '%s\n' "$captured" | awk -v end="$end" '
  index($0, end ":") == 1 {
    status = $0
    sub("^" end ":", "", status)
    print status
    exit
  }
')"

if [[ "$remote_status" =~ ^[0-9]+$ ]]; then
  echo "[exit $remote_status]"
  exit "$remote_status"
fi
