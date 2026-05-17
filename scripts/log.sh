#!/usr/bin/env bash

remote_tmux_log_enabled() {
  [ "${REMOTE_TMUX_LOG_ENABLED:-1}" != "0" ]
}

remote_tmux_log_dir() {
  printf '%s\n' "${REMOTE_TMUX_LOG_DIR:-$HOME/.codex/tmux-remote-linux/logs}"
}

remote_tmux_log_now() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

remote_tmux_log_epoch_ms() {
  local seconds
  seconds="$(date '+%s')"
  printf '%s000\n' "$seconds"
}

remote_tmux_log_request_id() {
  if [ -n "${REMOTE_TMUX_REQUEST_ID:-}" ]; then
    printf '%s\n' "$REMOTE_TMUX_REQUEST_ID"
    return 0
  fi

  printf '%s-%s\n' "$(date '+%Y%m%d-%H%M%S')" "$$"
}

remote_tmux_log_positive_integer_or_default() {
  local value="$1"
  local default_value="$2"

  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

remote_tmux_log_json_string() {
  awk '
    BEGIN {
      printf "\""
    }
    {
      if (NR > 1) {
        printf "\\n"
      }
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\t/, "\\t")
      gsub(/\r/, "\\r")
      printf "%s", $0
    }
    END {
      printf "\""
    }
  '
}

remote_tmux_log_cleanup() {
  local log_dir="$1"
  local retention_days

  retention_days="$(remote_tmux_log_positive_integer_or_default "${REMOTE_TMUX_LOG_RETENTION_DAYS:-7}" 7)"
  find "$log_dir" -type f -name '*.jsonl' -mtime +"$retention_days" -delete 2>/dev/null || true
}

remote_tmux_log_append_json() {
  local json_line="$1"
  local log_dir log_file

  remote_tmux_log_enabled || return 0

  log_dir="$(remote_tmux_log_dir)"
  (umask 077 && mkdir -p "$log_dir") 2>/dev/null || {
    echo "[tmux-remote-linux] unable to create log directory: $log_dir" >&2
    return 0
  }

  remote_tmux_log_cleanup "$log_dir"
  log_file="$log_dir/$(date '+%Y-%m-%d').jsonl"
  (umask 077 && printf '%s\n' "$json_line" >> "$log_file") 2>/dev/null || {
    echo "[tmux-remote-linux] unable to write log file: $log_file" >&2
    return 0
  }
}

remote_tmux_log_limited_output() {
  local max_lines="$1"

  awk -v max_lines="$max_lines" '
    NR <= max_lines {
      print
    }
  '
}

remote_tmux_log_line_count() {
  awk 'END { print NR + 0 }'
}

remote_tmux_log_is_truncated() {
  local max_lines="$1"
  local line_count="$2"

  if [ "$line_count" -gt "$max_lines" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

remote_tmux_log_run_event() {
  local script_name="$1"
  local request_id="$2"
  local target="$3"
  local environment="$4"
  local command_text="$5"
  local status="$6"
  local started_at="$7"
  local ended_at="$8"
  local duration_ms="$9"
  local exit_code="${10}"
  local output_text="${11}"
  local log_max_lines line_count truncated limited_output
  local request_id_json command_json output_json exit_code_json json_line

  remote_tmux_log_enabled || return 0

  log_max_lines="$(remote_tmux_log_positive_integer_or_default "${REMOTE_TMUX_LOG_MAX_OUTPUT_LINES:-10}" 10)"
  line_count="$(printf '%s' "$output_text" | remote_tmux_log_line_count)"
  truncated="$(remote_tmux_log_is_truncated "$log_max_lines" "$line_count")"
  limited_output="$(printf '%s' "$output_text" | remote_tmux_log_limited_output "$log_max_lines")"

  request_id_json="$(printf '%s' "$request_id" | remote_tmux_log_json_string)"
  command_json="$(printf '%s' "$command_text" | remote_tmux_log_json_string)"
  output_json="$(printf '%s' "$limited_output" | remote_tmux_log_json_string)"

  if [[ "$exit_code" =~ ^[0-9]+$ ]]; then
    exit_code_json="$exit_code"
  else
    exit_code_json="null"
  fi

  json_line="{\"schema_version\":1,\"tool\":\"tmux-remote-linux\",\"request_id\":$request_id_json,\"script\":\"$script_name\",\"target\":\"$target\",\"env\":\"$environment\",\"status\":\"$status\",\"command\":$command_json,\"started_at\":\"$started_at\",\"ended_at\":\"$ended_at\",\"duration_ms\":$duration_ms,\"exit_code\":$exit_code_json,\"output\":{\"text\":$output_json,\"max_lines\":$log_max_lines,\"line_count\":$line_count,\"truncated\":$truncated}}"
  remote_tmux_log_append_json "$json_line"
}

remote_tmux_log_send_event() {
  local script_name="$1"
  local request_id="$2"
  local target="$3"
  local environment="$4"
  local command_text="$5"
  local sent_at="$6"
  local request_id_json command_json json_line

  remote_tmux_log_enabled || return 0

  request_id_json="$(printf '%s' "$request_id" | remote_tmux_log_json_string)"
  command_json="$(printf '%s' "$command_text" | remote_tmux_log_json_string)"
  json_line="{\"schema_version\":1,\"tool\":\"tmux-remote-linux\",\"request_id\":$request_id_json,\"script\":\"$script_name\",\"target\":\"$target\",\"env\":\"$environment\",\"status\":\"sent\",\"command\":$command_json,\"sent_at\":\"$sent_at\",\"exit_code\":null,\"output\":null,\"note\":\"send.sh sends input and does not wait for command completion\"}"
  remote_tmux_log_append_json "$json_line"
}
