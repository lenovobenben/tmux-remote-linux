#!/usr/bin/env bash

remote_tmux_require_environment() {
  case "${REMOTE_TMUX_ENV:-}" in
    production|non-production)
      return 0
      ;;
    "")
      cat >&2 <<'EOF'
REMOTE_TMUX_ENV is required before using this tool.

Choose one explicitly:
  export REMOTE_TMUX_ENV=production
  export REMOTE_TMUX_ENV=non-production

Production mode requires explicit confirmation for each command before it is sent.
Non-production mode runs commands without production confirmation.
EOF
      exit 3
      ;;
    *)
      cat >&2 <<EOF
Invalid REMOTE_TMUX_ENV: ${REMOTE_TMUX_ENV}

Allowed values:
  production
  non-production
EOF
      exit 3
      ;;
  esac
}

remote_tmux_print_production_warning() {
  cat >&2 <<'EOF'
!!! You are about to let an AI-assisted workflow operate on a production environment.
!!! Review the command, target, and current shell context yourself before continuing.
!!! You are responsible for the result. The project authors and contributors are not liable for outages, data loss, security incidents, or other damage.

EOF
}

remote_tmux_random_digit() {
  local byte
  byte="$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' ')"
  if [[ "$byte" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$((byte % 10))"
    return 0
  fi

  awk 'BEGIN { srand(); print int(rand() * 10) }'
}

remote_tmux_validate_digit() {
  [[ "$1" =~ ^[0-9]$ ]]
}

remote_tmux_confirm_from_environment() {
  local expected="${REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT:-}"
  local actual="${REMOTE_TMUX_PROD_APPROVAL_DIGIT:-}"
  local explanation="${REMOTE_TMUX_COMMAND_EXPLANATION:-}"

  if ! remote_tmux_validate_digit "$expected" || ! remote_tmux_validate_digit "$actual"; then
    return 1
  fi

  if [ "$expected" != "$actual" ]; then
    return 1
  fi

  if [ -z "$explanation" ]; then
    return 1
  fi

  return 0
}

remote_tmux_confirm_if_production() {
  local command_text="$1"
  local explanation="${2:-${REMOTE_TMUX_COMMAND_EXPLANATION:-}}"

  if [ "${REMOTE_TMUX_ENV}" != "production" ]; then
    return 0
  fi

  if remote_tmux_confirm_from_environment; then
    return 0
  fi

  remote_tmux_print_production_warning

  if [ ! -t 0 ]; then
    cat >&2 <<'EOF'
Production command requires explicit confirmation.

Default is deny. For CLI use, run send.sh/run.sh from an interactive local
terminal and type the one-digit challenge shown by the script.

For Codex or another chat agent, approve the exact command in chat first. The
agent may then pass a one-time digit approval through:
  REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT
  REMOTE_TMUX_PROD_APPROVAL_DIGIT
  REMOTE_TMUX_COMMAND_EXPLANATION
EOF
    exit 4
  fi

  local digit
  digit="$(remote_tmux_random_digit)"

  cat >&2 <<EOF
PRODUCTION REMOTE COMMAND CONFIRMATION

Target: ${REMOTE_TMUX_TARGET:-remote:0.0}
Explanation:
${explanation:-No explanation provided. Review the command carefully.}

Command:
${command_text}

EOF

  local confirmation
  printf 'Type %s to send this command: ' "$digit" >&2
  IFS= read -r confirmation

  if [ "$confirmation" != "$digit" ]; then
    echo "Command was not sent." >&2
    exit 4
  fi
}
