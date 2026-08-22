#!/usr/bin/env bash
set -euo pipefail

# stage-iteration.sh — stage ONE benchmark iteration end-to-end. OPERATOR TOOL
# (Dave / any agent Matt hands this to). Automates the full between-runs
# procedure the E4 series established:
#
#   1. session-restart the participant agents (fresh context, no pod reboot)
#   2. reset matty-v/kessel-run to the pristine baseline (reset-run.sh)
#   3. file the run's task from a task file (issue-fill template, parked)
#   4. run Lando's validation gate against the filed issue
#   5. print the READY summary + the exact start command for the operator
#
# After it prints READY, a human pings Lando on Telegram:
#   start kessel-run#1 yolo
# Nothing self-starts — that ping is deliberately NOT scripted (charter: Matt
# is the only trigger).
#
# Requirements (see docs/EXPERIMENT.md § Staging):
#   - gh authenticated as matty-v with delete_repo scope
#   - env LANDO_WEBHOOK_SECRET   (shared Lando GitHub-webhook HMAC)
#   - env KYBER_FALCON_API_KEY   (falcon control-plane bearer key)
#   - env FDC -> falcon-dev-common clone (default ~/dev/falcon-dev-common)
#   - a task file (kept OUT of this template repo — task text landing in the
#     working repo would contaminate the benchmark; Dave holds the task bank)
#
# Task file format (plain text, three fenced sections after the header lines):
#   TITLE: <imperative issue title, <=70 chars>
#   SIZE: <XS|S|M|L|XL>          # T-shirt size, benchmark metric (Matt, 2026-08-19);
#                                # lands on the issue body and in the cost-ledger row
#   --- TLDR ---
#   <one or two sentences>
#   --- WHAT ---
#   <the body text>
#   --- AC ---
#   - [ ] <observable behavior>
#   - [ ] ...
#
# Usage:
#   FORCE=yes LANDO_WEBHOOK_SECRET=... KYBER_FALCON_API_KEY=... \
#     ./stage-iteration.sh --task-file <path> \
#     [--participants "lando yoda obi-wan ackbar han chewie"] \
#     [--labels "needs-triage,yolo,priority:asap,state:parked"] \
#     [--skip-restart] [--skip-reset]
#
# Fail-closed: any step failing aborts with the step named. No retries.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FDC="${FDC:-$HOME/dev/falcon-dev-common}"
# Self-heal the FDC clone: an operator clone left on a merged-then-deleted PR
# branch makes the reset step's pull fail ("no such ref was fetched") — bit the
# staging twice on 2026-08-22. Force it onto current main before anything runs.
if [ -d "$FDC/.git" ]; then
  git -C "$FDC" checkout -q main 2>/dev/null || true
  git -C "$FDC" pull -q --ff-only 2>/dev/null || true
fi
API="${KYBER_FALCON_API:-https://kyber-falcon.voget.io}"
CURL="${STAGE_CURL:-curl}"
GH="${STAGE_GH:-gh}"
REPO=matty-v/kessel-run

task_file=""; participants="lando yoda obi-wan ackbar han chewie"
labels="needs-triage,yolo,priority:asap,state:parked"
skip_restart=no; skip_reset=no
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file) task_file="$2"; shift 2 ;;
    --participants) participants="$2"; shift 2 ;;
    --labels) labels="$2"; shift 2 ;;
    --skip-restart) skip_restart=yes; shift ;;
    --skip-reset) skip_reset=yes; shift ;;
    *) echo "stage-iteration: unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n "$task_file" && -r "$task_file" ]] || { echo "stage-iteration: --task-file missing or unreadable" >&2; exit 2; }
[[ -d "$FDC" ]] || { echo "stage-iteration: falcon-dev-common clone not found at $FDC" >&2; exit 2; }
[[ "$skip_reset" = "yes" || -n "${LANDO_WEBHOOK_SECRET:-}" ]] || { echo "stage-iteration: LANDO_WEBHOOK_SECRET unset (needed by reset)" >&2; exit 2; }
[[ "$skip_restart" = "yes" || -n "${KYBER_FALCON_API_KEY:-}" ]] || { echo "stage-iteration: KYBER_FALCON_API_KEY unset (needed for session restarts)" >&2; exit 2; }

# ---- parse the task file ----------------------------------------------------
title="$(sed -n 's/^TITLE:[[:space:]]*//p' "$task_file" | head -1)"
[[ -n "$title" ]] || { echo "stage-iteration: STEP parse-task FAILED (no TITLE: line)" >&2; exit 1; }
size="$(sed -n 's/^SIZE:[[:space:]]*//p' "$task_file" | head -1)"
section() { # section <name> -> lines between "--- <name> ---" and the next "--- ... ---"/EOF
  awk -v s="--- $1 ---" '
    $0 == s {on=1; next}
    /^--- .* ---$/ {on=0}
    on {print}' "$task_file"
}
WORKDIR="$(mktemp -d)"; trap 'rm -rf "$WORKDIR"' EXIT
section TLDR > "$WORKDIR/tldr.txt"
section WHAT > "$WORKDIR/what.txt"
section AC   > "$WORKDIR/ac.txt"
for f in tldr what ac; do
  [[ -s "$WORKDIR/$f.txt" ]] || { echo "stage-iteration: STEP parse-task FAILED (empty --- ${f^^} --- section)" >&2; exit 1; }
done

# ---- 1. session-restart the participants ------------------------------------
if [[ "$skip_restart" != "yes" ]]; then
  restart_window_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "== 1. session-restart participants: $participants"
  for a in $participants; do
    code="$("$CURL" -sS -m 20 -X POST -H "Authorization: Bearer ${KYBER_FALCON_API_KEY}" \
      -o /dev/null -w '%{http_code}' "${API}/api/v1/agents/${a}/restart-session")" \
      || { echo "stage-iteration: STEP session-restart FAILED (${a}: curl error)" >&2; exit 1; }
    [[ "$code" = "200" ]] || { echo "stage-iteration: STEP session-restart FAILED (${a}: HTTP ${code})" >&2; exit 1; }
    echo "   ${a}: restarted"
  done
  echo "== 1b. verify participants Running"
  for a in $participants; do
    phase="$("$CURL" -sS -m 20 -H "Authorization: Bearer ${KYBER_FALCON_API_KEY}" \
      "${API}/api/v1/agents/${a}" | python3 -c "import json,sys;print(json.load(sys.stdin)['status']['phase'])")" \
      || { echo "stage-iteration: STEP verify-running FAILED (${a}: unreadable status)" >&2; exit 1; }
    [[ "$phase" = "Running" ]] || { echo "stage-iteration: STEP verify-running FAILED (${a}: phase=${phase})" >&2; exit 1; }
    echo "   ${a}: Running"
  done
  # External-binding race check (live 2026-08-19: kyber PR #95's review webhook
  # landed mid-session-restart and Chewie's session dropped it — 200 at the
  # binding, nothing processed, and side-job reviews have NO backstop). Warn on
  # any delivery to a worker-owned external webhook inside the restart window;
  # the operator decides whether to redeliver (an agent MAY have processed it).
  # Best-effort: never fails staging.
  for xr in matty-v/kyber matty-v/holocron; do
    "$GH" api "repos/${xr}/hooks" --jq \
      '.[] | select(.config.url | test("kyber-falcon.voget.io/webhooks/inbound/")) | .id' 2>/dev/null \
    | while read -r hid; do
        hits="$("$GH" api "repos/${xr}/hooks/${hid}/deliveries?per_page=10" \
          --jq ".[] | select(.delivered_at > \"${restart_window_start}\") | \"\(.id) \(.event).\(.action)\"" 2>/dev/null || true)"
        if [[ -n "$hits" ]]; then
          echo "   ⚠ WARNING: ${xr} webhook ${hid} delivered DURING the restart window — may have been dropped:"
          echo "$hits" | sed 's/^/     /'
          echo "     redeliver: gh api -X POST repos/${xr}/hooks/${hid}/deliveries/<id>/attempts"
        fi
      done || true
  done
else
  echo "== 1. session restarts SKIPPED (--skip-restart)"
fi

# ---- 2. repo reset ----------------------------------------------------------
if [[ "$skip_reset" != "yes" ]]; then
  echo "== 2. reset ${REPO} to baseline"
  FORCE="${FORCE:-}" LANDO_WEBHOOK_SECRET="$LANDO_WEBHOOK_SECRET" FDC="$FDC" \
    bash "${SCRIPT_DIR}/reset-run.sh" || { echo "stage-iteration: STEP reset FAILED" >&2; exit 1; }
else
  echo "== 2. repo reset SKIPPED (--skip-reset)"
fi

# ---- 3. file the task (template-assembled body, parked) ----------------------
echo "== 3. file the task: ${title}"
fill_args=(--tldr "$WORKDIR/tldr.txt" --what "$WORKDIR/what.txt" --ac "$WORKDIR/ac.txt")
[[ -n "$size" ]] && fill_args+=(--size "$size")
body_file="$(bash "${FDC}/scripts/issue-fill.sh" "${fill_args[@]}")" \
  || { echo "stage-iteration: STEP issue-fill FAILED" >&2; exit 1; }
label_args=(); IFS=',' read -ra ls <<<"$labels"
for l in "${ls[@]}"; do label_args+=(--label "$l"); done
issue_url="$("$GH" issue create -R "$REPO" --title "$title" --body-file "$body_file" "${label_args[@]}")" \
  || { echo "stage-iteration: STEP file-issue FAILED" >&2; exit 1; }
issue_num="${issue_url##*/}"
echo "   filed: ${issue_url}"

# ---- 4. validation gate ------------------------------------------------------
echo "== 4. validation gate"
gh_plain="$WORKDIR/gh-plain"; printf '#!/bin/bash\nexec %s "$@"\n' "$GH" > "$gh_plain"; chmod +x "$gh_plain"
FALCON_GH_ISSUE_OVERRIDE="$gh_plain" bash "${FDC}/scripts/validate-issue.sh" "$REPO" "$issue_num" \
  || { echo "stage-iteration: STEP gate FAILED — fix the filing before handing to Lando" >&2; exit 1; }

echo
echo "READY — iteration staged."
echo "Operator: ping Lando on Telegram:  start kessel-run#${issue_num} yolo"
