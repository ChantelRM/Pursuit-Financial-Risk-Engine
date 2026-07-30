#!/usr/bin/env bash
# ==============================================================================
# create_issues.sh
# Creates the 5 "infra expansion" issues on the Pursuit GitHub repo using the
# GitHub CLI (gh). One issue per phase, each with its own checklist.
#
# REQUIREMENTS (check these before running):
#   1. GitHub CLI installed: https://cli.github.com
#   2. Authenticated: run `gh auth login` once (accepts a Personal Access
#      Token the same way git push does) -- confirm with `gh auth status`
#   3. Run this from INSIDE your cloned repo directory, so gh knows which
#      repo to target. If you'd rather not clone, add --repo you/your-repo
#      to every `gh issue create` line below instead.
#
# WHERE TO RUN THIS: this script only manages GitHub issues -- it has
# nothing to do with R, Shiny, or Posit Cloud specifically. Easiest options,
# pick whichever is actually available to you:
#   - Posit Cloud's Terminal tab, IF gh is installed there and you run
#     `gh auth login` first (same token-auth flow as git)
#   - Your own laptop's terminal, if you have one outside the cloud setup
#   - GitHub Codespaces / VS Code's integrated terminal, if you clone there
#
# USAGE:
#   chmod +x create_issues.sh
#   ./create_issues.sh
# ==============================================================================

set -e

if ! command -v gh &> /dev/null; then
  echo "GitHub CLI (gh) not found. Install it from https://cli.github.com first."
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "Not authenticated. Run 'gh auth login' first, then re-run this script."
  exit 1
fi

echo "Creating issues on $(gh repo view --json nameWithOwner -q .nameWithOwner)..."

# ------------------------------------------------------------------------------
# PHASE 1
# ------------------------------------------------------------------------------
gh issue create \
  --title "Phase 1: Containerize the Shiny dashboard" \
  --body "$(cat <<'EOF'
**Suggested pace:** ~2 sessions this week

- [ ] Write a `Dockerfile` for the Shiny app (base R image, install required packages, copy `app.R` + `data/`, expose the Shiny port)
- [ ] Confirm it builds locally: `docker build -t pursuit-dashboard .`
- [ ] Confirm it runs and is reachable: `docker run -p 3838:3838 pursuit-dashboard`
- [ ] Add a short "Running with Docker" section to the README
- [ ] Commit the Dockerfile + README update
EOF
)"

# ------------------------------------------------------------------------------
# PHASE 2
# ------------------------------------------------------------------------------
gh issue create \
  --title "Phase 2: Turn the notebook pipeline into a real batch job" \
  --body "$(cat <<'EOF'
**Suggested pace:** ~2 sessions this week

- [ ] Extract the core pipeline logic (Sections 0-6 of the notebook) into a script that runs non-interactively via `Rscript`
- [ ] Swap flat-CSV outputs (`unified_ledger.csv`, `pursuit_rankings.csv`, etc.) for DuckDB tables as the actual storage layer -- reuses the DuckDB dependency already in place for querychat
- [ ] Confirm the dashboard's `app.R` can read from the DuckDB tables instead of the CSVs, or documents clearly why it still reads CSVs if that's the final call
- [ ] Update README to describe the pipeline as a script + database, not just a notebook
EOF
)"

# ------------------------------------------------------------------------------
# PHASE 3
# ------------------------------------------------------------------------------
gh issue create \
  --title "Phase 3: Add logging and automated tests" \
  --body "$(cat <<'EOF'
**Suggested pace:** ~2 sessions this week

- [ ] Add structured log lines to the batch script (timestamp, row counts in/out, pass/fail per stage)
- [ ] Install `testthat`, set up a `tests/` directory
- [ ] Write tests for `validate_schema()` (missing column, wrong type)
- [ ] Write a test for the `Critical_Alert` zero-balance rule (the manufactured test row from Issue 10, made permanent)
- [ ] Write a test confirming no duplicate `Debtor_ID`/`Record_ID` after merge
- [ ] Confirm `testthat::test_dir("tests")` runs clean locally
EOF
)"

# ------------------------------------------------------------------------------
# PHASE 4
# ------------------------------------------------------------------------------
gh issue create \
  --title "Phase 4: GitHub Actions CI" \
  --body "$(cat <<'EOF'
**Suggested pace:** ~2 sessions this week -- highest priority if time runs short

- [ ] Add `.github/workflows/ci.yml` that installs R + dependencies on push
- [ ] Run the `testthat` suite from Phase 3 in the workflow
- [ ] Run the batch pipeline script itself in the workflow (confirms it doesn't just pass tests, it actually executes end to end)
- [ ] Add the resulting status badge to the top of the README
- [ ] Confirm a deliberately broken push actually fails the workflow (sanity check that it's really running, not a false-green pass)
EOF
)"

# ------------------------------------------------------------------------------
# PHASE 5 (optional)
# ------------------------------------------------------------------------------
gh issue create \
  --title "Phase 5 (optional): Scheduled pipeline runs" \
  --body "$(cat <<'EOF'
**Suggested pace:** only if time allows -- lowest priority of the five

- [ ] Add a `schedule:` cron trigger to the GitHub Actions workflow (e.g. weekly)
- [ ] Confirm a scheduled run shows up in the Actions tab without a manual push
- [ ] Note in the README that this is a lightweight stand-in for real orchestration (Airflow/Prefect), not a claim of having built a scheduler from scratch
EOF
)"

echo "Done. Check the Issues tab on GitHub to confirm all 5 were created."
