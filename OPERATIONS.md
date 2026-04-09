# Operations

## Initial Setup

```bash
cd <notes-repo>
bash scripts/bootstrap.sh --code-repo <code-repo> --notes-repo <notes-repo>
bash scripts/verify-setup.sh --code-repo <code-repo> --notes-repo <notes-repo>
```

## Daily Usage

Code repo:

```bash
cd <code-repo>
git add ...
git commit -m "..."
git push
```

Notes repo:

```bash
cd <notes-repo>
node scripts/check-docs-governance.mjs --repo-root . --docs-dir .
git add .
git commit -m "docs: ..."
git push
```

## Full Audit

```bash
cd <notes-repo>
node scripts/check-docs-governance.mjs --all --repo-root . --docs-dir .
```

## Cron (Optional)

```bash
cd <notes-repo>
bash scripts/setup-cron.sh --code-repo <code-repo> --notes-repo <notes-repo> --schedule "15 2 * * *"
```
