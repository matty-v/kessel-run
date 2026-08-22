#!/usr/bin/env bash
set -euo pipefail

# test_stage_iteration.sh — offline test of stage-iteration.sh. Stubs the
# control-plane curl and gh; skips the (destructive) repo reset. Needs a
# falcon-dev-common clone at $FDC (default ~/dev/falcon-dev-common) for
# issue-fill/validate-issue — both run offline against the stub.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/stage-iteration.sh"
FDC="${FDC:-$HOME/dev/falcon-dev-common}"

PASS=0; FAIL=0
pass() { echo "[PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $*"; FAIL=$((FAIL + 1)); }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT

cat > "${SBX}/task.task" <<'EOF'
TITLE: Display run times as hours and minutes
SIZE: S
--- TLDR ---
Show the Time column as hours and minutes instead of decimal hours.
--- WHAT ---
The Time column currently shows decimal hours (e.g. "14.2"). Show it as hours and minutes.
--- AC ---
- [ ] Every row's time renders as "Xh Ym"; minutes are rounded to the nearest minute.
- [ ] Exact hours render as "Xh 0m".
- [ ] The conversion logic has unit tests.
EOF

# curl stub: restart-session -> 200; agent status -> Running
cat > "${SBX}/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do last="$a"; done
if [[ "$*" == *"restart-session"* ]]; then echo -n 200; else echo '{"status":{"phase":"Running"}}'; fi
EOF
chmod +x "${SBX}/curl"

# gh stub: issue create -> URL; api issues/9 -> the JSON validate-issue expects
# (body assembled by the REAL issue-fill so the gate genuinely validates it)
BODY_FILE="$(bash "${FDC}/scripts/issue-fill.sh" \
  --tldr <(sed -n '/--- TLDR ---/,/--- WHAT ---/p' "${SBX}/task.task" | sed '1d;$d') \
  --what <(sed -n '/--- WHAT ---/,/--- AC ---/p' "${SBX}/task.task" | sed '1d;$d') \
  --ac <(sed -n '/--- AC ---/,$p' "${SBX}/task.task" | sed '1d'))"
python3 - "$SBX" "$BODY_FILE" <<'PY'
import json, sys
sbx, bf = sys.argv[1:]
json.dump({"title": "Display run times as hours and minutes",
           "body": open(bf).read(),
           "labels": [{"name": n} for n in
                      ["needs-triage", "yolo", "priority:asap", "state:parked"]]},
          open(f"{sbx}/issue.json", "w"))
PY
cat > "${SBX}/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${SBX}/gh.log"
case "\$1 \$2" in
  "issue create")
    # capture the assembled body so the test can inspect it
    args=("\$@"); for i in "\${!args[@]}"; do
      [ "\${args[\$i]}" = "--body-file" ] && cp "\${args[\$((i+1))]}" "${SBX}/filed-body.md"
    done
    echo "https://github.com/matty-v/kessel-run/issues/9" ;;
  "api repos/matty-v/kessel-run/issues/9") cat "${SBX}/issue.json" ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "${SBX}/gh"

run_sut() { STAGE_CURL="${SBX}/curl" STAGE_GH="${SBX}/gh" KYBER_FALCON_API_KEY=test \
  FDC="$FDC" bash "$SUT" --task-file "${SBX}/task.task" --skip-reset "$@"; }

# 1. happy path: restarts + file + gate, READY with the start command
if out="$(run_sut 2>&1)"; then
  grep -q "READY" <<<"$out" && pass "stages to READY" || fail "no READY: $out"
  grep -q "start kessel-run#9 yolo" <<<"$out" && pass "prints the operator start command" || fail "no start command"
  grep -q "lando: Running" <<<"$out" && pass "verifies participants Running" || fail "no Running verification"
  grep -q -- "--label state:parked" "${SBX}/gh.log" && pass "files parked" || fail "not parked: $(grep 'issue create' "${SBX}/gh.log")"
  grep -q '^\*\*Size:\*\* S' "${SBX}/filed-body.md" && pass "SIZE: from the task file lands on the issue body" || fail "no Size line: $(head -2 "${SBX}/filed-body.md" 2>/dev/null)"
else fail "happy path failed: $out"; fi

# 2. fail-closed: missing API key aborts before touching anything
if out="$(STAGE_CURL="${SBX}/curl" STAGE_GH="${SBX}/gh" FDC="$FDC" bash "$SUT" --task-file "${SBX}/task.task" --skip-reset 2>&1)"; then
  fail "missing API key ACCEPTED"
else
  grep -q "KYBER_FALCON_API_KEY unset" <<<"$out" && pass "missing API key named" || fail "unnamed failure: $out"
fi

# 3. fail-closed: malformed task file (no TITLE) aborts
sed '1d' "${SBX}/task.task" > "${SBX}/bad.task"
if run_sut_out="$(STAGE_CURL="${SBX}/curl" STAGE_GH="${SBX}/gh" KYBER_FALCON_API_KEY=t FDC="$FDC" \
    bash "$SUT" --task-file "${SBX}/bad.task" --skip-reset 2>&1)"; then
  fail "task without TITLE accepted"
else
  grep -q "no TITLE" <<<"$run_sut_out" && pass "missing TITLE named" || fail "unnamed: $run_sut_out"
fi

echo
echo "stage-iteration: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
