#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/log.sh
source "$script_dir/log.sh"

usage() {
  cat <<'EOF'
usage: logs.sh [--dir <log-dir>] <command> [args]

Commands:
  path                    Print the active log directory.
  list                    List JSONL log files.
  last [N]                Show the last N events as a summary table. Default: 10.
  today [N]               Show today's last N events as a summary table. Default: 10.
  failures [N]            Show the last N run.sh events with non-zero exit codes. Default: 20.
  grep <pattern> [N]      Search commands and captured output. Default: 20.
  show <request_id>       Pretty-print the event with this request_id.
  output <request_id>     Print only output.text for this request_id.

Environment:
  REMOTE_TMUX_LOG_DIR     Override the default log directory.
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "logs.sh requires jq to query JSONL logs" >&2
    exit 2
  fi
}

positive_or_default() {
  local value="${1:-}"
  local default_value="$2"

  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

log_files() {
  local log_dir="$1"

  [ -d "$log_dir" ] || return 0
  find "$log_dir" -type f -name '*.jsonl' -print | sort
}

cat_logs() {
  local log_dir="$1"
  local file

  while IFS= read -r file; do
    [ -n "$file" ] && cat "$file"
  done < <(log_files "$log_dir")
}

summary_jq='[.started_at // .sent_at // "-", .request_id // "-", .script // "-", .status // "-", ((.exit_code // "null") | tostring), .target // "-", .command // "-"] | @tsv'

print_summary_header() {
  printf 'time\trequest_id\tscript\tstatus\texit\ttarget\tcommand\n'
}

log_dir=""
if [ "${1:-}" = "--dir" ]; then
  if [ "$#" -lt 3 ]; then
    usage >&2
    exit 2
  fi
  log_dir="$2"
  shift 2
fi

log_dir="${log_dir:-$(remote_tmux_log_dir)}"
command_name="${1:-}"

case "$command_name" in
  path)
    printf '%s\n' "$log_dir"
    ;;
  list)
    log_files "$log_dir"
    ;;
  last)
    require_jq
    count="$(positive_or_default "${2:-}" 10)"
    print_summary_header
    cat_logs "$log_dir" | tail -n "$count" | jq -r "$summary_jq"
    ;;
  today)
    require_jq
    count="$(positive_or_default "${2:-}" 10)"
    today_file="$log_dir/$(date '+%Y-%m-%d').jsonl"
    print_summary_header
    [ -f "$today_file" ] && tail -n "$count" "$today_file" | jq -r "$summary_jq"
    ;;
  failures)
    require_jq
    count="$(positive_or_default "${2:-}" 20)"
    print_summary_header
    cat_logs "$log_dir" | jq -r 'select(.script == "run.sh" and (.exit_code // 0) != 0) | '"$summary_jq" | tail -n "$count"
    ;;
  grep)
    require_jq
    if [ "$#" -lt 2 ]; then
      usage >&2
      exit 2
    fi
    pattern="$2"
    count="$(positive_or_default "${3:-}" 20)"
    print_summary_header
    cat_logs "$log_dir" | jq -r --arg pattern "$pattern" 'select(((.command // "") | contains($pattern)) or (((.output.text // "") | contains($pattern)))) | '"$summary_jq" | tail -n "$count"
    ;;
  show)
    require_jq
    if [ "$#" -lt 2 ]; then
      usage >&2
      exit 2
    fi
    request_id="$2"
    cat_logs "$log_dir" | jq --arg request_id "$request_id" 'select(.request_id == $request_id)'
    ;;
  output)
    require_jq
    if [ "$#" -lt 2 ]; then
      usage >&2
      exit 2
    fi
    request_id="$2"
    cat_logs "$log_dir" | jq -r --arg request_id "$request_id" 'select(.request_id == $request_id) | .output.text // ""'
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
