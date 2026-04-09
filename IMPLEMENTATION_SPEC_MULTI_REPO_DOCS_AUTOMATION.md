# Implementation Spec: Multi-Repo Docs Automation

## Purpose

Define a reusable automation pattern where:

1. The code repository remains clean and never commits mounted notes.
2. Notes/governance scripts live only in the notes repository.
3. Setup is repeatable on a new machine with one bootstrap command.

## Repositories

- Code repo: variable (`--code-repo <path>`)
- Notes repo: variable (`--notes-repo <path>`, default current repo)
- Mounted entry in code repo: variable (`--mount-name <name>`, default `.local-docs`)

## Non-Goals

- No modifications to tracked files in the upstream code repo.
- No hardcoded repo names (for example `openclaw`, `clawlens`) in generic scripts.

## Required Scripts (notes repo only)

1. `scripts/bootstrap.sh`
2. `scripts/verify-setup.sh`
3. `scripts/setup-cron.sh`
4. `scripts/check-docs-governance.mjs`

## CLI Contract

All shell scripts accept (where applicable):

- `--code-repo <path>`
- `--notes-repo <path>` (default: current repo)
- `--mount-name <name>` (default: `.local-docs`)
- `--dry-run` (show actions only, only for scripts that write local state)

`setup-cron.sh` additionally accepts:

- `--schedule "<cron expr>"`

## Bootstrap Behavior

`bootstrap.sh` must:

1. Validate `code-repo` and `notes-repo` are git repositories.
2. Resolve absolute paths and write a state file:
   - `notes-repo/.bootstrap-state.json`
3. Create/update mount:
   - `code-repo/<mount-name>` points to `notes-repo` (symlink).
4. Ensure local exclude:
   - `code-repo/.git/info/exclude` contains `<mount-name>/`.
5. Install/merge pre-commit guard in code repo:
   - Block staging paths matching `^<mount-name>(/|$)`.
6. Install notes-repo hooks (optional local quality checks).
7. Print final summary and next steps.

## Hook Merge Strategy (No Clobber)

Never overwrite existing hooks.

Rules:

1. If hook file does not exist, create a standard shell header.
2. Append managed snippet with markers:
   - `# >>> managed-by-notes-bootstrap >>>`
   - `# <<< managed-by-notes-bootstrap <<<`
3. If marker block already exists, replace only that block.
4. Preserve all non-managed user/framework content.

## Verify Behavior

`verify-setup.sh` must be non-destructive and fail fast on mismatch:

1. State file exists and JSON parse succeeds.
2. Symlink exists and target equals absolute `notes-repo` path.
3. `info/exclude` contains `<mount-name>/`.
4. Hook marker block exists in code repo pre-commit.
5. Notes repo remote exists (origin).

Exit code:

- `0`: all checks pass
- non-`0`: at least one mismatch

## Cron Behavior

`setup-cron.sh` must:

1. Read absolute paths from state file (or explicit args).
2. Write cron entry using absolute node/script paths.
3. Log to:
   - `notes-repo/reports/automation.log`
4. Be idempotent (update existing managed cron line, no duplicates).

## Docs Governance Checker Requirements

`check-docs-governance.mjs` must:

1. Support staged mode by default and `--all`.
2. Avoid repo-name hardcoding.
3. Keep history index validation label-agnostic:
   - allow any link text as long as target file matches.
4. Return non-zero on policy violations.

## Security and Safety

1. No destructive git operations.
2. No writes outside `code-repo` local git metadata and `notes-repo`.
3. `--dry-run` prints intended writes/updates without changing files.

## Migration Checklist

1. Clone code repo.
2. Clone notes repo.
3. Run bootstrap with parameters.
4. Run verify.
5. Optionally install cron.

## Acceptance Criteria

1. Notes committed in notes repo are not visible as tracked changes in code repo.
2. If user stages mount path in code repo, pre-commit blocks commit.
3. Re-running bootstrap produces no duplicate blocks/entries.
4. verify returns success on healthy setup and non-zero on tampering.
