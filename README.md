# Kessel Run

The galaxy's smuggling-run leaderboard — who made the Kessel Run in the fewest parsecs.

A small React + Vite static site, deployed to GitHub Pages: https://matty-v.github.io/kessel-run/

## About this repo

Kessel Run is a benchmarking workbench for an AI dev team ([Kyber](https://github.com/matty-v/kyber) agents). Features are built here through the team's normal issue → PR → review → deploy workflow so the cost and quality of that workflow can be measured under controlled conditions.

Because experiments are repeated, **this repo's history is disposable**: it is periodically deleted and recreated from a clean baseline. Don't fork it expecting stability, and don't be surprised when issue numbers restart at #1.

## Develop

```bash
npm ci
npm run dev    # local dev server
npm test       # unit tests
npm run build  # typecheck + production build
```

Operator-side benchmark controls are documented in
[`docs/EXPERIMENT.md`](docs/EXPERIMENT.md). Verify the fail-closed run preflight
with `bash scripts/test_preflight_run.sh`.
