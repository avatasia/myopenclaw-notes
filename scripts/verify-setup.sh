#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/verify-setup.sh [--code-repo <path>] [--notes-repo <path>] [--mount-name <name>]
EOF
}

CODE_REPO=""
NOTES_REPO=""
MOUNT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --code-repo) CODE_REPO="$2"; shift 2 ;;
    --notes-repo) NOTES_REPO="$2"; shift 2 ;;
    --mount-name) MOUNT_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$NOTES_REPO" ]]; then
  NOTES_REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
else
  NOTES_REPO="$(cd "$NOTES_REPO" && pwd -P)"
fi

STATE_FILE="$NOTES_REPO/.bootstrap-state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "Missing state file: $STATE_FILE"
  exit 1
fi

STATE_VALUES="$(node -e "const fs=require('node:fs');const s=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write([s.codeRepo||'',s.notesRepo||'',s.mountName||''].join('\t'));" "$STATE_FILE")"
IFS=$'\t' read -r STATE_CODE_REPO STATE_NOTES_REPO STATE_MOUNT_NAME <<< "$STATE_VALUES"

if [[ -z "$CODE_REPO" ]]; then CODE_REPO="$STATE_CODE_REPO"; fi
if [[ -z "$MOUNT_NAME" ]]; then MOUNT_NAME="$STATE_MOUNT_NAME"; fi

CODE_REPO="$(cd "$CODE_REPO" && pwd -P)"
EXPECTED_NOTES_REPO="$(cd "$NOTES_REPO" && pwd -P)"
MOUNT_PATH="$CODE_REPO/$MOUNT_NAME"
EXCLUDE_FILE="$CODE_REPO/.git/info/exclude"
CODE_HOOK="$CODE_REPO/.git/hooks/pre-commit"
NOTES_HOOK="$NOTES_REPO/.git/hooks/pre-commit"
GITIGNORE_FILE="$NOTES_REPO/.gitignore"
REPORTS_DIR="$NOTES_REPO/reports"
MANAGED_START="# >>> managed-by-notes-bootstrap >>>"

fail=0

if [[ "$STATE_NOTES_REPO" != "$EXPECTED_NOTES_REPO" ]]; then
  echo "Mismatch: state notesRepo != current notes repo"
  fail=1
fi

if [[ "$MOUNT_PATH" == "$EXPECTED_NOTES_REPO" ]]; then
  :
elif [[ ! -L "$MOUNT_PATH" ]]; then
  echo "Missing mount symlink: $MOUNT_PATH"
  fail=1
else
  TARGET="$(node -e "const fs=require('node:fs');process.stdout.write(fs.realpathSync(process.argv[1]));" "$MOUNT_PATH" 2>/dev/null || true)"
  if [[ "$TARGET" != "$EXPECTED_NOTES_REPO" ]]; then
    echo "Mount target mismatch: $MOUNT_PATH -> $TARGET"
    fail=1
  fi
fi

if [[ ! -f "$EXCLUDE_FILE" ]] || ! grep -qxF "$MOUNT_NAME/" "$EXCLUDE_FILE"; then
  echo "Missing exclude rule in $EXCLUDE_FILE: $MOUNT_NAME/"
  fail=1
fi

if [[ ! -f "$CODE_HOOK" ]] || ! grep -qF "$MANAGED_START" "$CODE_HOOK"; then
  echo "Missing managed block in code pre-commit hook"
  fail=1
fi

if [[ ! -f "$NOTES_HOOK" ]] || ! grep -qF "$MANAGED_START" "$NOTES_HOOK"; then
  echo "Missing managed block in notes pre-commit hook"
  fail=1
fi

if [[ ! -d "$REPORTS_DIR" ]]; then
  echo "Missing reports directory: $REPORTS_DIR"
  fail=1
fi

if [[ ! -f "$GITIGNORE_FILE" ]] || ! grep -qxF ".bootstrap-state.json" "$GITIGNORE_FILE"; then
  echo "Missing .gitignore rule in notes repo: .bootstrap-state.json"
  fail=1
fi
if [[ ! -f "$GITIGNORE_FILE" ]] || ! grep -qxF "reports/automation.log" "$GITIGNORE_FILE"; then
  echo "Missing .gitignore rule in notes repo: reports/automation.log"
  fail=1
fi

if ! git -C "$NOTES_REPO" remote get-url origin >/dev/null 2>&1; then
  echo "Missing notes repo origin remote"
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "verify failed"
  exit 1
fi

echo "verify passed"
