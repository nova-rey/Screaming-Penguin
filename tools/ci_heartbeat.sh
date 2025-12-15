#!/usr/bin/env bash
set -euo pipefail

HEARTBEAT_INTERVAL_SECONDS=300
HEARTBEAT_LABEL="command"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --interval)
      HEARTBEAT_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --label)
      HEARTBEAT_LABEL="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$#" -eq 0 ]]; then
  echo "[CI-HEARTBEAT] ERROR: Missing command to run."
  echo "[CI-HEARTBEAT] Usage: $0 [--label name] [--interval seconds] -- <command>"
  exit 1
fi

CMD=("$@")

echo "[CI-HEARTBEAT] Stage '${HEARTBEAT_LABEL}' started (heartbeat every ${HEARTBEAT_INTERVAL_SECONDS}s)."

CMD_PID=""
HB_PID=""

cleanup() {
  if [[ -n "${HB_PID}" ]]; then
    kill "${HB_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${CMD_PID}" ]]; then
    kill "${CMD_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

"${CMD[@]}" &
CMD_PID=$!

(
  while kill -0 "${CMD_PID}" >/dev/null 2>&1; do
    printf '[CI-HEARTBEAT] %s still running at %s\n' "${HEARTBEAT_LABEL}" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    sleep "${HEARTBEAT_INTERVAL_SECONDS}"
  done
) &
HB_PID=$!

wait "${CMD_PID}"
STATUS=$?

cleanup
wait "${HB_PID}" >/dev/null 2>&1 || true

if [[ "${STATUS}" -eq 0 ]]; then
  echo "[CI-HEARTBEAT] Stage '${HEARTBEAT_LABEL}' completed successfully."
else
  echo "[CI-HEARTBEAT] Stage '${HEARTBEAT_LABEL}' exited with status ${STATUS}."
fi

exit "${STATUS}"
