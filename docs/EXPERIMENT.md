# Kessel Run — Experiment Reset & Run Process

Kessel Run is the Falcon Dev Team's benchmarking workbench: the team re-implements
frozen tasks on this repo under controlled conditions so cost and workflow can be
measured run-over-run. This document captures the repeatable process. The repo you
are reading regenerates from `matty-v/kessel-run-template` at every reset — that
template is where this file durably lives.

**Deliberately NOT in this repo (or the template):** the frozen task bank and the
per-run reports. Both live in the operator's private repo — a task bank in the
working repo would reveal the roadmap, and a run report describes a prior
implementation; either one contaminates future runs.

## Staging (scripted — the one-command path)

`scripts/stage-iteration.sh` runs the whole between-runs procedure below in one
command (added 2026-08-19 for the E4 hardening/baseline series; hand-over-able
to any operator agent):

```bash
FORCE=yes LANDO_WEBHOOK_SECRET=<lando github HMAC> KYBER_FALCON_API_KEY=<falcon bearer key> \
  scripts/stage-iteration.sh --task-file <path to task file>
```

It session-restarts the participants (`restart-session` — NOT pod reboots; pods
only need rebooting when a shipped vendor/identity fix must be picked up),
verifies each is Running, resets the repo (reset-run.sh), files the task parked
via the falcon-dev-common issue template, runs Lando's validation gate, and
prints the exact start command. The operator then pings Lando on Telegram:
`start kessel-run#<n> yolo` — starting is deliberately never scripted (charter:
Matt is the only trigger). Task files stay OUT of this repo (they'd land in the
working repo on recreation = contamination); Dave holds the task bank and the
task-file format is documented in the script header. Offline tests:
`scripts/test_stage_iteration.sh`.

## Per-run protocol (operator, manual steps — what the script automates)

1. **Define** the run: ID, task(s), variable under test, participating agents.
   Record in the run report BEFORE starting.
2. **Cost gate**: confirm the PREVIOUS run's closing cost summary/ledger row exists
   before any teardown — recycling the coordinator or deleting the repo mid
   close-path destroys the cost data.
3. **Reset** the repo: `FORCE=yes LANDO_WEBHOOK_SECRET=... scripts/reset-run.sh`
   (delete → recreate from template → Pages → labels → webhook → layer-1 checks →
   baseline deploy verified). Repo-level state (Pages config, labels, webhooks)
   dies with the repo every time; the script re-applies all of it.
4. **Recycle** every participating agent's session (control-plane
   `POST /api/v1/agents/{name}/restart`), and wait for the pod to actually cycle —
   the phase alone lies. Verify fresh context via the token gauges after each
   agent's first turn.
5. **File** the task issue verbatim from the bank with labels
   `needs-triage + priority:asap + yolo + state:parked`. No builder/stage
   pre-labels — triage grounds and strips unearned ones. `yolo` is the charter's
   autonomous-through-merge switch; without it the pipeline stops at the human
   merge gate.
6. **Preflight**: run `scripts/preflight-run.sh` with the frozen task JSON,
   participant sweep evidence, old pod-IP snapshot, previous repository ID and
   previous immutable ledger key. It must emit `{"ready":true,…}`. Any failure
   stops the run; do not release the issue.
7. **Release**: remove `state:parked`. That timestamp opens the metrics window.
8. **Observe only.** Any operator message to the team mid-run is logged as an
   intervention. Watch for: pickup + usage-baseline comment pairs (a missing
   baseline degrades stage pricing), and approved-but-unmerged PRs (a stalled
   merge means the yolo label is missing or the coordinator gated).
9. **Collect metrics** when the issue closes: per-stage `falcon:usage:v1` footers
   on the issue/PR, the coordinator's cost ledger row, wall clock un-park→merge.
10. **Sweep** (memory hygiene): run the shared `benchmark-sweep.sh` in `audit`
    then `clean` mode for every worker and retain its JSON evidence for the next
    preflight. Lando is audit-only: preserve his ledger, reports and operational
    logs. The builder's `falcon:workspace:v1` marker must match the live
    repository identity; missing evidence invalidates the run.
11. **Report**, then the next run starts at step 1.

## Contamination layers (what the reset actually guarantees)

| layer | vector | mitigation |
|---|---|---|
| 1 | git history + closed PRs/issues | repo delete + recreate (the ONLY thing that wipes closed items) |
| 2 | agent session context | session recycle before each run, freshness verified |
| 3 | agent long-term memory | repo-guide no-persist rule + post-run sweep |
| 4 | Discord chatter | fresh thread per run; accepted minor risk |
| 5 | shared team docs | post-run sweep |
| 6 | pod-local clones/branches (survive BOTH repo resets and pod restarts) | repo-guide fresh-clone rule + per-run attestation check |

## Gotchas (learned the hard way)

- Pages config, labels, branch protection and webhooks all die with the repo.
- The team's spec-attestation stage REWRITES the issue body into the standard
  template — "verbatim" holds only at filing time.
- A freshly recycled agent's token gauge reads the PREVIOUS session until its
  first real turn.
- Repo-scoped verbal rules don't rewire label-keyed mechanisms: the `yolo` label
  is what actually authorizes autonomous merge, per the team charter.
- The working repo may vanish briefly around a reset. That is expected.
