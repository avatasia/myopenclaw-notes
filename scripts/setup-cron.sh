#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/setup-cron.sh [--code-repo <path>] [--notes-repo <path>] [--mount-name <name>] [--schedule "<cron expr>"] [--dry-run]
EOF
}

CODE_REPO=""
NOTES_REPO=""
MOUNT_NAME=""
SCHEDULE="15 2 * * *"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --code-repo) CODE_REPO="$2"; shift 2 ;;
    --notes-repo) NOTES_REPO="$2"; shift 2 ;;
    --mount-name) MOUNT_NAME="$2"; shift 2 ;;
    --schedule) SCHEDULE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$NOTES_REPO" ]]; then
  NOTES_REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
else
  NOTES_REPO="$(cd "$NOTES_REPO" && pwd -P)"
fi

if ! [[ "$SCHEDULE" =~ ^([^[:space:]]+[[:space:]]+){4}[^[:space:]]+$ ]]; then
  echo "Invalid --schedule format: expected 5 cron fields"
  exit 1
fi

STATE_FILE="$NOTES_REPO/.bootstrap-state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "Missing state file: $STATE_FILE"
  exit 1
fi

STATE_VALUES="$(node -e "const fs=require('node:fs');const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write([s.codeRepo||'',s.mountName||''].join('\t'));" "$STATE_FILE")"
IFS=$'\t' read -r STATE_CODE_REPO STATE_MOUNT_NAME <<< "$STATE_VALUES"
if [[ -z "$CODE_REPO" ]]; then CODE_REPO="$STATE_CODE_REPO"; fi
if [[ -z "$MOUNT_NAME" ]]; then MOUNT_NAME="$STATE_MOUNT_NAME"; fi

CODE_REPO="$(cd "$CODE_REPO" && pwd -P)"
LOG_FILE="$NOTES_REPO/reports/automation.log"
NODE_BIN="$(command -v node)"
CHECKER="$NOTES_REPO/scripts/check-docs-governance.mjs"
MARKER="# managed-by-notes-bootstrap"

if [[ ! -x "$NODE_BIN" ]]; then
  echo "node executable not found"
  exit 1
fi
if [[ ! -f "$CHECKER" ]]; then
  echo "Missing checker script: $CHECKER"
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] mkdir -p '$NOTES_REPO/reports'"
else
  mkdir -p "$NOTES_REPO/reports"
fi

CRON_CMD="cd \"$NOTES_REPO\" && \"$NODE_BIN\" \"$CHECKER\" --all --repo-root \"$NOTES_REPO\" --docs-dir . >> \"$LOG_FILE\" 2>&1"
CRON_LINE="$SCHEDULE $CRON_CMD $MARKER"

EXISTING="$(crontab -l 2>/dev/null || true)"
FILTERED="$(printf '%s\n' "$EXISTING" | grep -vF "$MARKER" || true)"
if [[ -n "$FILTERED" ]]; then
  NEW_CRON="$FILTERED"$'\n'"$CRON_LINE"$'\n'
else
  NEW_CRON="$CRON_LINE"$'\n'
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] would install cron line:"
  echo "$CRON_LINE"
  exit 0
fi

printf '%s' "$NEW_CRON" | crontab -
echo "cron installed/updated"
echo "schedule: $SCHEDULE"
echo "log: $LOG_FILE"
