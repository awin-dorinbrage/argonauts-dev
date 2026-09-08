#!/usr/bin/env bash
# Start advertiser-support local stack from ~/work sibling repos.
#
# Usage (from anywhere):
#   ~/work/start-advertiser-support.sh wiremock
#   ~/work/start-advertiser-support.sh services
#   ~/work/start-advertiser-support.sh stop
#
# Override the work dir if needed:
#   WORK_DIR=/path/to/work ~/work/start-advertiser-support.sh wiremock
#
# Ctrl+C stops everything this script started.

set -euo pipefail

WORK="${WORK_DIR:-$HOME/work}"
UI="$WORK/advertiser-support-ui"
SHELL_UI="$WORK/shell-ui"
SERVICE="$WORK/advertiser-support-service"
LOCALIZATION="$WORK/nova-localization"
ENV_FILE="$UI/src/environments/environment.ts"
ENV_BACKUP=""

MODE="${1:-}"
PIDS=()

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: ~/work/start-advertiser-support.sh <wiremock|services|stop>

Repos (under ~/work):
  shell-ui                            Nova host — started in both modes
  advertiser-support-ui               Support remote — started in both modes
  advertiser-support-service          SAM API — services mode only
  nova-localization                   translations only (not started)
  advertiser-support-service-authorizer
                                      not started (SAM has a local authorizer)

  wiremock   UIs + UI WireMocks
             Tickets → http://localhost:8085
             Open     → http://localhost:4200/en/awin/advertiser/1001/support

  services   UIs + advertiser-support-service (SAM)
             Skips UI ticket WireMock. Points the UI at SAM :3006.
             Tickets → http://localhost:3006
             SAM still uses its own Salesforce stubs on :8086.
             Open     → http://localhost:4200/en/awin/advertiser/1001/support

  stop       kill listeners on the local ports and SAM's WireMock container

Both modes keep shell-ui WireMock on :8080 (Nova user/accounts/nav). Auth0 is always real.
EOF
}

need_dir() {
  [[ -d "$1" ]] || { red "Missing repo: $1"; exit 1; }
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { red "Missing command: $1"; exit 1; }
}

port_pids() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true
}

kill_port() {
  local port="$1"
  local pids
  pids="$(port_pids "$port")"
  if [[ -n "$pids" ]]; then
    ylw "Stopping process(es) on :$port ($pids)"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 1
    pids="$(port_pids "$port")"
    if [[ -n "$pids" ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
  fi
}

restore_env() {
  if [[ -n "$ENV_BACKUP" && -f "$ENV_BACKUP" ]]; then
    mv "$ENV_BACKUP" "$ENV_FILE"
    ylw "Restored $ENV_FILE"
    ENV_BACKUP=""
  fi
}

cleanup() {
  restore_env
  if ((${#PIDS[@]})); then
    ylw "Stopping started processes: ${PIDS[*]}"
    kill "${PIDS[@]}" 2>/dev/null || true
  fi
  if [[ "$MODE" == "services" ]]; then
    (cd "$SERVICE" && make local-dev-down) || true
  fi
}

point_ui_at_sam() {
  ENV_BACKUP="$(mktemp)"
  cp "$ENV_FILE" "$ENV_BACKUP"
  # macOS BSD sed
  sed -i '' "s|export const baseUrl = 'http://localhost:8085';|export const baseUrl = 'http://localhost:3006';|" "$ENV_FILE"
  if grep -q "localhost:3006" "$ENV_FILE"; then
    ylw "Pointed advertiser-support-ui at SAM http://localhost:3006"
  else
    red "Failed to patch $ENV_FILE — leave it pointing at :3006 manually"
    exit 1
  fi
}

run_bg() {
  local dir="$1"
  shift
  (
    cd "$dir"
    "$@"
  ) &
  PIDS+=("$!")
}

stop_all() {
  for port in 4200 4206 8080 8085 3006; do
    kill_port "$port"
  done
  if [[ -d "$SERVICE" ]]; then
    (cd "$SERVICE" && make local-dev-down) || true
  fi
  grn "Stopped local listeners (and SAM WireMock container if present)."
}

if [[ "$MODE" != "wiremock" && "$MODE" != "services" && "$MODE" != "stop" ]]; then
  usage
  exit 1
fi

if [[ "$MODE" == "stop" ]]; then
  stop_all
  exit 0
fi

need_dir "$WORK"
need_dir "$UI"
need_dir "$SHELL_UI"
need_dir "$LOCALIZATION"
need_cmd yarn
need_cmd java
need_cmd lsof

if [[ "$MODE" == "services" ]]; then
  need_dir "$SERVICE"
  need_cmd sam
  need_cmd docker
  docker info >/dev/null 2>&1 || { red "Docker is not running."; exit 1; }
fi

trap cleanup EXIT INT TERM

grn "Using work dir: $WORK"
grn "Clearing local ports…"
kill_port 4200
kill_port 4206
kill_port 8080
kill_port 8085
if [[ "$MODE" == "services" ]]; then
  kill_port 3006
  point_ui_at_sam
fi

grn "Starting shell-ui WireMock (:8080)…"
run_bg "$SHELL_UI" yarn wiremock

if [[ "$MODE" == "wiremock" ]]; then
  grn "Starting advertiser-support-ui WireMock (:8085)…"
  run_bg "$UI" yarn wiremock
else
  grn "Starting advertiser-support-service (SAM :3006, Salesforce stubs :8086)…"
  run_bg "$SERVICE" make local-dev-up
fi

grn "Starting advertiser-support-ui (:4206)…"
# Avoid yarn start's -o, which opens the standalone remote (Auth0 will fail there).
run_bg "$UI" yarn ng serve advertiser-support

grn "Starting shell-ui (:4200)…"
run_bg "$SHELL_UI" yarn start

cat <<EOF

$(grn "Stack is coming up ($MODE).")
  Support UI   http://localhost:4200/en/awin/advertiser/1001/support
  Remote only  http://localhost:4206/advertiser-support   (don't use this)
  Shell mock   http://localhost:8080
EOF

if [[ "$MODE" == "wiremock" ]]; then
  echo "  Ticket mock  http://localhost:8085"
else
  echo "  SAM API      http://localhost:3006"
  echo "  SF stubs     http://localhost:8086"
fi

echo
ylw "Auth0 login at id.dev.awin.com is expected. Ctrl+C stops the stack."
echo

wait
