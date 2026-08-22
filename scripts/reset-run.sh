#!/usr/bin/env bash
set -euo pipefail

# reset-run.sh — reset matty-v/kessel-run to the pristine baseline for a new
# benchmark run. OPERATOR TOOL (Dave/Matt): needs `gh` authenticated as matty-v
# with delete_repo scope, and LANDO_WEBHOOK_SECRET in env (the shared Lando
# GitHub-webhook HMAC; operators hold it — it is never committed anywhere).
#
# What a reset destroys BY DESIGN: git history, all issues and PRs (closed ones
# included — the only way to wipe them), stars/watches, Pages config, labels,
# webhooks. What it recreates: everything, from matty-v/kessel-run-template.
#
# Usage: FORCE=yes LANDO_WEBHOOK_SECRET=... ./reset-run.sh

REPO=matty-v/kessel-run
TEMPLATE=matty-v/kessel-run-template
FDC="${FDC:-$HOME/dev/falcon-dev-common}"   # clone of matty-v/falcon-dev-common

[ "${FORCE:-}" = "yes" ] || { echo "refusing: set FORCE=yes (this DELETES ${REPO})"; exit 2; }
[ -n "${LANDO_WEBHOOK_SECRET:-}" ] || { echo "refusing: LANDO_WEBHOOK_SECRET unset"; exit 2; }
[ -d "$FDC" ] || { echo "refusing: falcon-dev-common clone not found at $FDC"; exit 2; }

echo "== 1. delete + recreate from template"
gh repo delete "$REPO" --yes
gh repo create "$REPO" --template "$TEMPLATE" --public >/dev/null
sleep 8   # template content population is async

echo "== 2. re-enable Pages (dies with the repo — mandatory every reset)"
gh api -X POST "repos/${REPO}/pages" -f build_type=workflow --jq .build_type

echo "== 3. re-apply falcon labels + reinstall the Lando webhook (both die with the repo)"
(cd "$FDC" && git pull -q && scripts/apply-labels-and-templates.sh --repo kessel-run)
(cd "$FDC" && LANDO_WEBHOOK_SECRET="$LANDO_WEBHOOK_SECRET" scripts/install-lando-webhook.sh --repo kessel-run)

echo "== 4. layer-1 verification"
created=$(gh api "repos/${REPO}" --jq .created_at); echo "created_at: $created"
commits=$(gh api "repos/${REPO}/commits" --jq length); echo "commits: $commits (expect 1)"
prs=$(gh pr list -R "$REPO" --state all | wc -l);   echo "PRs: $prs (expect 0)"
issues=$(gh issue list -R "$REPO" --state all | wc -l); echo "issues: $issues (expect 0)"
[ "$commits" = "1" ] && [ "$prs" = "0" ] && [ "$issues" = "0" ] || { echo "LAYER-1 CHECK FAILED"; exit 1; }

echo "== 5. wait for baseline deploy, verify site"
# GitHub registers a recreated repo's workflows ASYNCHRONOUSLY. Until that
# lands, the generation push fires nothing, `gh workflow run` says "could not
# find any workflows", and the old bare status-poll here spun forever (live
# 2026-08-19: 7+ min hang, zero runs). So: wait for registration (bounded),
# dispatch deploy if the push-trigger never fired, then wait (bounded).
tries=0
until [ "$(gh api "repos/${REPO}/actions/workflows" --jq '.workflows | length' 2>/dev/null || echo 0)" -ge 1 ]; do
  tries=$((tries+1)); [ "$tries" -ge 30 ] && { echo "WORKFLOWS NEVER REGISTERED (5 min)"; exit 1; }
  sleep 10
done
if [ "$(gh run list -R "$REPO" --workflow=deploy --limit 1 --json status --jq length 2>/dev/null)" != "1" ]; then
  echo "   deploy did not fire on the generation push — dispatching manually"
  gh workflow run deploy.yml -R "$REPO"
  sleep 10
fi
tries=0
until [ "$(gh run list -R "$REPO" --workflow=deploy --limit 1 --json status --jq '.[0].status' 2>/dev/null)" = "completed" ]; do
  tries=$((tries+1)); [ "$tries" -ge 60 ] && { echo "DEPLOY NEVER COMPLETED (10 min)"; exit 1; }
  sleep 10
done
gh run list -R "$REPO" --workflow=deploy --limit 1
concl="$(gh run list -R "$REPO" --workflow=deploy --limit 1 --json conclusion --jq '.[0].conclusion')"
[ "$concl" = "success" ] || { echo "DEPLOY FAILED (conclusion: $concl)"; exit 1; }
# Pages can lag the deploy by a few seconds — bounded retry, not one shot.
tries=0; code=000
until code=$(curl -s -o /dev/null -w '%{http_code}' https://matty-v.github.io/kessel-run/); [ "$code" = "200" ]; do
  tries=$((tries+1)); [ "$tries" -ge 12 ] && break
  sleep 10
done
echo "site: $code"; [ "$code" = "200" ] || { echo "SITE NOT LIVE"; exit 1; }

echo "RESET COMPLETE — repo is at the pristine baseline."
echo "Next (operator, see docs/EXPERIMENT.md): recycle participant agent sessions,"
echo "then file the run's task (verbatim, parked) and un-park to open the window."
