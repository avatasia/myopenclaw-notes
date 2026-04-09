#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/bootstrap.sh --code-repo <path> [--notes-repo <path>] [--mount-name <name>] [--dry-run]
EOF
}

CODE_REPO=""
NOTES_REPO=""
MOUNT_NAME=".local-docs"
DRY_RUN=0
declare -A DRY_CREATED_FILES
declare -A DRY_APPENDED_LINES

while [[ $# -gt 0 ]]; do
  case "$1" in
    --code-repo) CODE_REPO="$2"; shift 2 ;;
    --notes-repo) NOTES_REPO="$2"; shift 2 ;;
    --mount-name) MOUNT_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$CODE_REPO" ]]; then
  echo "Missing required argument: --code-repo"
  usage
  exit 1
fi

if [[ -z "$NOTES_REPO" ]]; then
  NOTES_REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
fi

CODE_REPO="$(cd "$CODE_REPO" && pwd -P)"
NOTES_REPO="$(cd "$NOTES_REPO" && pwd -P)"
MOUNT_PATH="$CODE_REPO/$MOUNT_NAME"
STATE_FILE="$NOTES_REPO/.bootstrap-state.json"
GITIGNORE_FILE="$NOTES_REPO/.gitignore"
EXCLUDE_FILE="$CODE_REPO/.git/info/exclude"
CODE_HOOK="$CODE_REPO/.git/hooks/pre-commit"
NOTES_HOOK="$NOTES_REPO/.git/hooks/pre-commit"

MANAGED_START="# >>> managed-by-notes-bootstrap >>>"
MANAGED_END="# <<< managed-by-notes-bootstrap <<<"

ensure_line_in_file() {
  local file="$1"
  local line="$2"
  local line_key="${file}::${line}"

  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ ! -f "$file" ]] && [[ -z "${DRY_CREATED_FILES[$file]:-}" ]]; then
      echo "[dry-run] create file: $file"
      DRY_CREATED_FILES[$file]=1
    fi
    if [[ -z "${DRY_APPENDED_LINES[$line_key]:-}" ]]; then
      echo "[dry-run] append line to $file: $line"
      DRY_APPENDED_LINES[$line_key]=1
    fi
    return
  fi

  if [[ ! -f "$file" ]]; then
    touch "$file"
  fi
  printf '%s\n' "$line" >> "$file"
}

ensure_git_repo() {
  local repo="$1"
  if [[ ! -d "$repo/.git" ]]; then
    echo "Not a git repository: $repo"
    exit 1
  fi
}

replace_or_append_managed_block() {
  local file="$1"
  local block_file="$2"

  if [[ ! -f "$file" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] create hook file: $file"
      return
    fi
    cat > "$file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v start="$MANAGED_START" -v end="$MANAGED_END" '
    BEGIN { skip=0 }
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    skip == 0 { print }
  ' "$file" > "$tmp"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] update managed block in $file"
    rm -f "$tmp"
    return
  fi

  {
    cat "$tmp"
    echo
    cat "$block_file"
  } > "$file"
  chmod +x "$file"
  rm -f "$tmp"
}

ensure_git_repo "$CODE_REPO"
ensure_git_repo "$NOTES_REPO"

if [[ -z "$MOUNT_NAME" ]] || [[ "$MOUNT_NAME" == *"/"* ]] || ! [[ "$MOUNT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "--mount-name must be a non-empty single segment matching [a-zA-Z0-9._-]"
  exit 1
fi

if [[ "$MOUNT_PATH" == "$NOTES_REPO" ]]; then
  :
elif [[ -L "$MOUNT_PATH" ]]; then
  target="$(readlink "$MOUNT_PATH")"
  if [[ "$target" != "$NOTES_REPO" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] rm '$MOUNT_PATH'"
      echo "[dry-run] ln -s '$NOTES_REPO' '$MOUNT_PATH'"
    else
      rm "$MOUNT_PATH"
      ln -s "$NOTES_REPO" "$MOUNT_PATH"
    fi
  fi
elif [[ -e "$MOUNT_PATH" ]]; then
  echo "Mount path exists but is not symlink: $MOUNT_PATH"
  exit 1
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] ln -s '$NOTES_REPO' '$MOUNT_PATH'"
  else
    ln -s "$NOTES_REPO" "$MOUNT_PATH"
  fi
fi

if [[ ! -f "$EXCLUDE_FILE" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] create file: $EXCLUDE_FILE"
    DRY_CREATED_FILES[$EXCLUDE_FILE]=1
  else
    touch "$EXCLUDE_FILE"
  fi
fi
ensure_line_in_file "$EXCLUDE_FILE" "$MOUNT_NAME/"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] mkdir -p '$NOTES_REPO/reports'"
else
  mkdir -p "$NOTES_REPO/reports"
fi
ensure_line_in_file "$GITIGNORE_FILE" ".bootstrap-state.json"
ensure_line_in_file "$GITIGNORE_FILE" "reports/automation.log"

code_block="$(mktemp)"
cat > "$code_block" <<EOF
$MANAGED_START
ROOT="\$(git rev-parse --show-toplevel)"
cd "\$ROOT"
if git diff --cached --name-only | grep -Eq '^${MOUNT_NAME//./\\.}(/|\$)'; then
  echo "Blocked: ${MOUNT_NAME} changes must not be committed to code repo."
  exit 1
fi
$MANAGED_END
EOF
replace_or_append_managed_block "$CODE_HOOK" "$code_block"
rm -f "$code_block"

notes_block="$(mktemp)"
cat > "$notes_block" <<EOF
$MANAGED_START
ROOT="\$(git rev-parse --show-toplevel)"
cd "\$ROOT"
node scripts/check-docs-governance.mjs --repo-root "\$ROOT" --docs-dir .
$MANAGED_END
EOF
replace_or_append_managed_block "$NOTES_HOOK" "$notes_block"
rm -f "$notes_block"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] write $STATE_FILE"
else
  cat > "$STATE_FILE" <<EOF
{
  "codeRepo": "$CODE_REPO",
  "notesRepo": "$NOTES_REPO",
  "mountName": "$MOUNT_NAME",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
fi

echo "bootstrap completed"
echo "code-repo: $CODE_REPO"
echo "notes-repo: $NOTES_REPO"
echo "mount: $MOUNT_NAME"
