#!/usr/bin/env bash
set -euo pipefail

# Fail-closed readiness gate immediately before un-parking a Kessel Run task.
# Performs no writes. The task JSON is private operator input: {title,body}.

REPO="${KESSEL_REPO:-matty-v/kessel-run}"
API="${FALCON_API_URL:-https://kyber-falcon.voget.io/api/v1}"
SITE="${KESSEL_SITE_URL:-https://matty-v.github.io/kessel-run/}"
participants=(lando yoda obi-wan ackbar han chewie)
run_id=""; issue=""; task_json=""; old_pods=""; sweep_dir=""
previous_repo_id=""; previous_key=""; ledger_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id) run_id="$2"; shift 2 ;; --issue) issue="$2"; shift 2 ;;
    --task-json) task_json="$2"; shift 2 ;; --old-pods-json) old_pods="$2"; shift 2 ;;
    --sweep-dir) sweep_dir="$2"; shift 2 ;; --previous-repository-id) previous_repo_id="$2"; shift 2 ;;
    --previous-ledger-key) previous_key="$2"; shift 2 ;; --ledger-file) ledger_file="$2"; shift 2 ;;
    *) echo "preflight-run.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ "$run_id" =~ ^R-[0-9]{8}-[a-z]+$ ]] || { echo "preflight-run.sh: invalid --run-id" >&2; exit 2; }
[[ "$issue" =~ ^[0-9]+$ && -r "$task_json" && -r "$old_pods" && -d "$sweep_dir" ]] || {
  echo "preflight-run.sh: required input missing" >&2; exit 2;
}
[[ -n "${USER_FALCON_API_KEY:-}" ]] || { echo "preflight-run.sh: USER_FALCON_API_KEY unset" >&2; exit 2; }
if [[ -n "$previous_key" ]]; then
  [[ -r "$ledger_file" ]] || { echo "preflight-run.sh: previous key requires --ledger-file" >&2; exit 2; }
  jq -e --arg k "$previous_key" 'select(.ledger_key==$k)|.totals|has("priced")' "$ledger_file" >/dev/null || {
    echo "preflight-run.sh: previous run has no terminal ledger row" >&2; exit 1;
  }
fi

# Lando is deliberately excluded: his accounting is preserved, not swept.
for agent in yoda obi-wan ackbar han chewie; do
  evidence="${sweep_dir}/${agent}.json"
  [[ -r "$evidence" ]] && jq -e --arg a "$agent" '.agent==$a and .repo=="matty-v/kessel-run" and .clean==true' "$evidence" >/dev/null || {
    echo "preflight-run.sh: clean sweep evidence missing for $agent" >&2; exit 1;
  }
done

repo_json="$(gh api "repos/${REPO}")"; repo_id="$(jq -r .id <<<"$repo_json")"
[[ -z "$previous_repo_id" || "$repo_id" != "$previous_repo_id" ]] || { echo "preflight-run.sh: repository ID did not change" >&2; exit 1; }
commits="$(gh api "repos/${REPO}/commits?per_page=2" --jq length)"
prs="$(gh api "repos/${REPO}/pulls?state=all&per_page=2" --jq length)"
issues="$(gh api "repos/${REPO}/issues?state=all&per_page=10" --jq '[.[]|select(has("pull_request")|not)]|length')"
[[ "$commits" == 1 && "$prs" == 0 && "$issues" == 1 ]] || { echo "preflight-run.sh: layer-1 state mismatch" >&2; exit 1; }

issue_json="$(gh api "repos/${REPO}/issues/${issue}")"
jq -e --slurpfile task "$task_json" '.title==$task[0].title and .body==$task[0].body and ([.labels[].name]|sort)==(["needs-triage","priority:asap","state:parked","yolo"]|sort)' <<<"$issue_json" >/dev/null || {
  echo "preflight-run.sh: frozen task or label set mismatch" >&2; exit 1;
}

agents_json="$(curl -fsS -H "Authorization: Bearer ${USER_FALCON_API_KEY}" "$API/agents")"
for agent in "${participants[@]}"; do
  old_ip="$(jq -r --arg a "$agent" '.[$a]' "$old_pods")"
  jq -e --arg a "$agent" --arg old "$old_ip" '.items[]|select(.id==$a)|.status.phase=="Running" and (.status.podIP|length)>0 and .status.podIP!=$old' <<<"$agents_json" >/dev/null || {
    echo "preflight-run.sh: $agent not Running on a replacement pod IP" >&2; exit 1;
  }
done
[[ "$(curl -fsS -o /dev/null -w '%{http_code}' "$SITE")" == 200 ]] || { echo "preflight-run.sh: baseline site not live" >&2; exit 1; }

jq -n --arg run_id "$run_id" --argjson repository_id "$repo_id" --arg issue_node_id "$(jq -r .node_id <<<"$issue_json")" \
  --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ready:true,run_id:$run_id,repository_id:$repository_id,issue_node_id:$issue_node_id,checked_at:$checked_at}'

