#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SUT="$ROOT/scripts/preflight-run.sh"
SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/bin" "$SBX/sweeps"
printf '{"title":"Show the number of logged runs in the header","body":"frozen body"}\n' > "$SBX/task.json"
printf '{"lando":".19","yoda":".17","obi-wan":".24","ackbar":".22","han":".18","chewie":".21"}\n' > "$SBX/old.json"
for a in yoda obi-wan ackbar han chewie; do printf '{"agent":"%s","repo":"matty-v/kessel-run","clean":true}\n' "$a" > "$SBX/sweeps/$a.json"; done
cat > "$SBX/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  repos/matty-v/kessel-run) echo '{"id":2002}' ;;
  'repos/matty-v/kessel-run/commits?per_page=2') echo 1 ;;
  'repos/matty-v/kessel-run/pulls?state=all&per_page=2') echo 0 ;;
  'repos/matty-v/kessel-run/issues?state=all&per_page=10') echo 1 ;;
  repos/matty-v/kessel-run/issues/1) echo '{"node_id":"I_NEW","title":"Show the number of logged runs in the header","body":"frozen body","labels":[{"name":"needs-triage"},{"name":"priority:asap"},{"name":"state:parked"},{"name":"yolo"}]}' ;;
  *) exit 1 ;;
esac
EOF
cat > "$SBX/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *api/v1/agents*) echo '{"items":[{"id":"lando","status":{"phase":"Running","podIP":".25"}},{"id":"yoda","status":{"phase":"Running","podIP":".26"}},{"id":"obi-wan","status":{"phase":"Running","podIP":".30"}},{"id":"ackbar","status":{"phase":"Running","podIP":".31"}},{"id":"han","status":{"phase":"Running","podIP":".29"}},{"id":"chewie","status":{"phase":"Running","podIP":".32"}}]}' ;;
  *) printf 200 ;;
esac
EOF
chmod +x "$SBX/bin/gh" "$SBX/bin/curl"
OUT="$(PATH="$SBX/bin:$PATH" USER_FALCON_API_KEY=x "$SUT" --run-id R-20260818-a --issue 1 --task-json "$SBX/task.json" --old-pods-json "$SBX/old.json" --sweep-dir "$SBX/sweeps" --previous-repository-id 1001)"
jq -e '.ready==true and .repository_id==2002 and .issue_node_id=="I_NEW"' <<<"$OUT" >/dev/null
echo "[PASS] clean run preflight"
printf '{"agent":"han","repo":"matty-v/kessel-run","clean":false}\n' > "$SBX/sweeps/han.json"
if PATH="$SBX/bin:$PATH" USER_FALCON_API_KEY=x "$SUT" --run-id R-20260818-b --issue 1 --task-json "$SBX/task.json" --old-pods-json "$SBX/old.json" --sweep-dir "$SBX/sweeps" >/dev/null 2>&1; then
  echo "[FAIL] dirty sweep accepted"; exit 1
fi
echo "[PASS] dirty sweep refused"
