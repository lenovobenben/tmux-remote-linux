#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/env_guard.sh
source "$script_dir/env_guard.sh"
# shellcheck source=scripts/log.sh
source "$script_dir/log.sh"
remote_tmux_require_environment

target="${REMOTE_TMUX_TARGET:-remote:0.0}"
wait_seconds="${REMOTE_TMUX_RUN_WAIT_SECONDS:-1}"
capture_lines="${REMOTE_TMUX_RUN_CAPTURE_LINES:-400}"
marker_capture_lines="${REMOTE_TMUX_RUN_MARKER_CAPTURE_LINES:-5000}"
begin_timeout_seconds="${REMOTE_TMUX_RUN_BEGIN_TIMEOUT_SECONDS:-5}"
max_output_lines="${REMOTE_TMUX_RUN_MAX_OUTPUT_LINES:-200}"
max_output_bytes="${REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES:-32768}"
pending_output_lines="${REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES:-40}"
detect_interactive="${REMOTE_TMUX_DETECT_INTERACTIVE:-1}"
avoid_remote_history="${REMOTE_TMUX_AVOID_REMOTE_HISTORY:-1}"
prompt_guard="${REMOTE_TMUX_PROMPT_GUARD:-1}"

# 31D763DA06 is hexadecimal digits 91-100 after the point in e.
# It is a fixed magic prefix for the managed prompt, not a security token.
managed_prompt_prefix="__31D763DA06_TRL"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 '<command>'" >&2
  exit 2
fi

for numeric_value in "$wait_seconds" "$capture_lines" "$marker_capture_lines" "$begin_timeout_seconds" "$max_output_lines" "$max_output_bytes" "$pending_output_lines"; do
  if ! [[ "$numeric_value" =~ ^[0-9]+$ ]]; then
    echo "run.sh configuration values must be non-negative integers" >&2
    exit 2
  fi
done

if [ "$capture_lines" -le 0 ] || [ "$marker_capture_lines" -le 0 ] || [ "$max_output_lines" -le 0 ] || [ "$max_output_bytes" -le 0 ] || [ "$pending_output_lines" -le 0 ]; then
  echo "run.sh line and byte limits must be positive" >&2
  exit 2
fi

if [ "$marker_capture_lines" -lt "$capture_lines" ]; then
  marker_capture_lines="$capture_lines"
fi

case "$prompt_guard" in
  0|1)
    ;;
  *)
    echo "REMOTE_TMUX_PROMPT_GUARD must be 0 or 1" >&2
    exit 2
    ;;
esac

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

send_remote_command() {
  local command_to_send="$1"

  if [ "$avoid_remote_history" = "0" ]; then
    tmux send-keys -t "$target" -l -- "$command_to_send"
  else
    tmux send-keys -t "$target" -l -- " export HISTCONTROL=ignoreboth:erasedups; setopt HIST_IGNORE_SPACE 2>/dev/null || true; $command_to_send; __tmux_remote_hist_id=\$(HISTTIMEFORMAT= history 1 2>/dev/null | awk '{print \$1}'); [ -n \"\$__tmux_remote_hist_id\" ] && history -d \"\$__tmux_remote_hist_id\" 2>/dev/null || true; unset __tmux_remote_hist_id"
  fi
  tmux send-keys -t "$target" Enter
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
[run.sh] REPL-style interactive input is not supported. Exit or handle the REPL manually, or use a one-shot non-interactive command such as mysql -e, redis-cli <command>, python -c, or node -e.
EOF
      exit 5
      ;;
  esac
}

stale_marker_followed_by_managed_prompt() {
  local pane_text="$1"
  local marker="$2"

  printf '%s\n' "$pane_text" | awk -v marker="$marker" -v prefix="$managed_prompt_prefix" '
    index($0, marker) > 0 { seen_marker = 1; next }
    seen_marker && index($0, prefix "_") > 0 { found_prompt = 1 }
    END { exit found_prompt ? 0 : 1 }
  '
}

detect_stale_run() {
  local recent b end_marker
  recent="$(tmux capture-pane -J -t "$target" -p -S "-$marker_capture_lines")"
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    end_marker="${b/BEGIN__/END__}"
    if ! printf '%s\n' "$recent" | grep -qF "$end_marker"; then
      if [ "$prompt_guard" = "1" ]; then
        if stale_marker_followed_by_managed_prompt "$recent" "$b"; then
          continue
        fi
        if ensure_managed_prompt >/dev/null; then
          recent="$(tmux capture-pane -J -t "$target" -p -S "-$marker_capture_lines")"
          if stale_marker_followed_by_managed_prompt "$recent" "$b"; then
            continue
          fi
        fi
      fi
      cat >&2 <<EOF
[run.sh] stale run marker detected: $b
[run.sh] A previous run.sh command may still be running or its output was lost.
[run.sh] Use read.sh to inspect the pane. Wait for completion or send Ctrl-C to recover.
EOF
      exit 6
    fi
  done < <(printf '%s\n' "$recent" | grep -oE '__CODEX_RUN_[0-9]+_[0-9]+_BEGIN__' || true)
}

latest_managed_prompt_state() {
  tmux capture-pane -J -t "$target" -p -S "-$marker_capture_lines" | awk -v prefix="$managed_prompt_prefix" '
    {
      line = $0
      regex = prefix "_[0-9]+_[0-9]+__"
      while (match(line, regex)) {
        token = substr(line, RSTART, RLENGTH)
        value = token
        sub("^" prefix "_", "", value)
        sub("__$", "", value)
        split(value, parts, "_")
        counter = parts[1]
        status = parts[2]
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END {
      if (counter != "" && status != "") {
        print counter, status
      }
    }
  '
}

current_managed_prompt_state() {
  tmux capture-pane -J -t "$target" -p -S "-20" | awk -v prefix="$managed_prompt_prefix" '
    NF { last = $0 }
    END {
      regex = prefix "_[0-9]+_[0-9]+__"
      if (match(last, regex)) {
        token = substr(last, RSTART, RLENGTH)
        value = token
        sub("^" prefix "_", "", value)
        sub("__$", "", value)
        split(value, parts, "_")
        print parts[1], parts[2]
      }
    }
  '
}

ensure_managed_prompt() {
  local prompt_state init_command

  prompt_state="$(current_managed_prompt_state)"
  if [ -n "$prompt_state" ]; then
    printf '%s\n' "$prompt_state"
    return 0
  fi

  init_command="if [ -z \"\${BASH_VERSION:-}\" ]; then "
  init_command+="echo '[run.sh] managed prompt requires an interactive bash shell' >&2; "
  init_command+="else export __TRL_COUNTER=0; "
  init_command+="PROMPT_COMMAND='__trl_status=\$?; "
  init_command+="__TRL_COUNTER=\$((\${__TRL_COUNTER:-0} + 1)); "
  init_command+="PS1=\"${managed_prompt_prefix}_\${__TRL_COUNTER}_\${__trl_status}__ \"'; fi"

  send_remote_command "$init_command"
  for ((i = 0; i <= begin_timeout_seconds; i++)); do
    sleep 1
    prompt_state="$(latest_managed_prompt_state)"
    if [ -n "$prompt_state" ]; then
      printf '%s\n' "$prompt_state"
      return 0
    fi
  done

  echo "[run.sh] managed prompt initialization did not produce a bash prompt token" >&2
  echo "[run.sh] prompt guard currently supports ordinary interactive bash shells only" >&2
  return 1
}

managed_prompt_counter_advanced() {
  local previous_counter="$1"
  local prompt_state counter

  prompt_state="$(latest_managed_prompt_state)"
  counter="${prompt_state%% *}"
  [[ "$counter" =~ ^[0-9]+$ ]] && [ "$counter" -gt "$previous_counter" ]
}

command_text="$1"
request_id="$(remote_tmux_log_request_id)"

if [ "$detect_interactive" != "0" ]; then
  detect_interactive_prompt
fi

remote_tmux_confirm_if_production "$command_text"

started_at="$(remote_tmux_log_now)"
started_ms="$(remote_tmux_log_epoch_ms)"

detect_stale_run

prompt_counter_before=""
if [ "$prompt_guard" = "1" ]; then
  prompt_state_before="$(ensure_managed_prompt)" || {
    ended_at="$(remote_tmux_log_now)"
    ended_ms="$(remote_tmux_log_epoch_ms)"
    remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "prompt_init_not_found" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 124 ""
    exit 124
  }
  prompt_counter_before="${prompt_state_before%% *}"
fi

marker="CODEX_RUN_$(date +%s)_$$"
begin="__${marker}_BEGIN__"
end="__${marker}_END__"

encoded_command="$(printf '%s' "$command_text" | base64 | tr -d '\n')"
inner_command="printf '\n%s\n' '$begin'; printf '%s' '$encoded_command' | base64 -d | bash; __codex_status=\$?; printf '\n%s:%s\n' '$end' \"\$__codex_status\""
encoded_inner_command="$(printf '%s' "$inner_command" | base64 | tr -d '\n')"
remote_command="printf '%s' '$encoded_inner_command' | base64 -d | HISTFILE=/dev/null HISTCONTROL=ignorespace:ignoredups bash"

send_remote_command "$remote_command"
sleep "$wait_seconds"

captured="$(tmux capture-pane -t "$target" -p -S "-$marker_capture_lines")"

if ! printf '%s\n' "$captured" | grep -Fxq "$begin"; then
  for ((i = 0; i < begin_timeout_seconds; i++)); do
    sleep 1
    captured="$(tmux capture-pane -t "$target" -p -S "-$marker_capture_lines")"
    if printf '%s\n' "$captured" | grep -Fxq "$begin"; then
      break
    fi
  done
fi

if ! printf '%s\n' "$captured" | grep -Fxq "$begin"; then
  ended_at="$(remote_tmux_log_now)"
  ended_ms="$(remote_tmux_log_epoch_ms)"
  if [ "$prompt_guard" = "1" ] && managed_prompt_counter_advanced "$prompt_counter_before"; then
    remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "begin_not_found_shell_idle" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 124 ""
    echo "[run.sh] begin marker not found, but the managed prompt returned; shell appears idle" >&2
    echo "[run.sh] command output and exit status could not be recovered from markers" >&2
    exit 124
  fi
  remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "begin_not_found" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 124 ""
  echo "[run.sh] begin marker not found yet: $begin" >&2
  echo "[run.sh] not printing pane history; use read.sh 40 if you need to inspect the current pane" >&2
  exit 124
fi

if ! printf '%s\n' "$captured" | grep -q "^${end}:"; then
  pending_output="$(printf '%s\n' "$captured" | awk -v begin="$begin" -v max_lines="$pending_output_lines" '
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
  ')"
  limited_pending_output="$(printf '%s' "$pending_output" | limit_output)"
  if [ -n "$limited_pending_output" ]; then
    printf '%s\n' "$limited_pending_output"
  fi
  ended_at="$(remote_tmux_log_now)"
  ended_ms="$(remote_tmux_log_epoch_ms)"
  if [ "$prompt_guard" = "1" ] && managed_prompt_counter_advanced "$prompt_counter_before"; then
    remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "end_not_found_shell_idle" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 124 "$pending_output"
    echo "[run.sh] end marker not found, but the managed prompt returned; shell appears idle" >&2
    echo "[run.sh] command output and exit status could not be fully recovered from markers" >&2
    exit 124
  fi
  remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "pending" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 124 "$pending_output"
  echo "[run.sh] end marker not found yet; command may still be running" >&2
  exit 124
fi

command_output="$(printf '%s\n' "$captured" | awk -v begin="$begin" -v end="$end" '
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
')"
limited_command_output="$(printf '%s' "$command_output" | limit_output)"
if [ -n "$limited_command_output" ]; then
  printf '%s\n' "$limited_command_output"
fi

remote_status="$(printf '%s\n' "$captured" | awk -v end="$end" '
  index($0, end ":") == 1 {
    status = $0
    sub("^" end ":", "", status)
    print status
    exit
  }
')"

if [[ "$remote_status" =~ ^[0-9]+$ ]]; then
  echo "[request_id $request_id]"
  echo "[exit $remote_status]"
  ended_at="$(remote_tmux_log_now)"
  ended_ms="$(remote_tmux_log_epoch_ms)"
  remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "completed" "$started_at" "$ended_at" "$((ended_ms - started_ms))" "$remote_status" "$command_output"
  exit "$remote_status"
fi

ended_at="$(remote_tmux_log_now)"
ended_ms="$(remote_tmux_log_epoch_ms)"
remote_tmux_log_run_event "run.sh" "$request_id" "$target" "$REMOTE_TMUX_ENV" "$command_text" "exit_parse_error" "$started_at" "$ended_at" "$((ended_ms - started_ms))" 1 "$command_output"
echo "[run.sh] unable to parse remote exit status" >&2
exit 1
