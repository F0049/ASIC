#!/usr/bin/env bash
# Run the RTL-to-GDSII flow in Docker with one command.
#
#   scripts/run_flow.sh                 # uses ./config.json
#   scripts/run_flow.sh path/to.json    # other config
#   scripts/run_flow.sh --smoke-test    # built-in sanity check, no design needed
#
# Each run gets a tag like  dev-terr_20261018_153012  so runs from different
# branches never overwrite each other. Results are copied into export/<tag>/
# (final GDS, netlists, LEF...) and reports/<tag>/ (reports + metrics).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- pick the flow CLI from the project venv
CLI=".venv/bin/librelane"
[[ -x "$CLI" ]] || CLI=".venv/bin/openlane"
[[ -x "$CLI" ]] || die "No flow CLI in .venv. Run scripts/setup.sh first."

# --- start Docker Desktop if it isn't running, and wait for it
if ! docker info >/dev/null 2>&1; then
  say "Starting Docker Desktop..."
  open -a Docker
  for _ in $(seq 1 60); do
    docker info >/dev/null 2>&1 && break
    sleep 2
  done
  docker info >/dev/null 2>&1 || die "Docker did not come up within 2 minutes."
fi

# --- smoke test mode
if [[ "${1:-}" == "--smoke-test" ]]; then
  exec "$CLI" --dockerized --smoke-test
fi

CONFIG="${1:-config.json}"
[[ -f "$CONFIG" ]] || die "Config not found: $CONFIG"

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null | tr '/' '-' || echo detached)"
TAG="${BRANCH}_$(date +%Y%m%d_%H%M%S)"
RUN_DIR="runs/$TAG"

say "Running flow  (tag: $TAG)"
"$CLI" --dockerized --run-tag "$TAG" "$CONFIG"

# --- copy results into the project's standard folders
if [[ -d "$RUN_DIR/final" ]]; then
  mkdir -p "export/$TAG"
  cp -R "$RUN_DIR/final/." "export/$TAG/"
  say "Final outputs -> export/$TAG/"
fi

if [[ -d "$RUN_DIR" ]]; then
  mkdir -p "reports/$TAG"
  while IFS= read -r f; do
    mkdir -p "reports/$TAG/$(dirname "$f")"
    cp "$RUN_DIR/$f" "reports/$TAG/$f"
  done < <(cd "$RUN_DIR" && find . -type f \( -name '*.rpt' -o -name 'metrics.json' -o -name 'metrics.csv' \))
  say "Reports -> reports/$TAG/"
fi

GDS="$(find "export/$TAG" -name '*.gds' 2>/dev/null | head -n 1 || true)"
[[ -n "$GDS" ]] && echo "View layout:  open -a klayout \"$GDS\""
exit 0
