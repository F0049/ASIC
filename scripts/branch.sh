#!/usr/bin/env bash
# Branch workflow helper.
#
#   scripts/branch.sh init  <name>            first-time: make 'main' + your branch dev/<name>
#   scripts/branch.sh start <name>            new branch dev/<name> from main (you or a colleague)
#   scripts/branch.sh sync                    bring latest main into the branch you're on
#   scripts/branch.sh promote [-m "msg"] <paths...>
#                                             copy ONLY the given files/folders from your branch onto main
#                                             as one commit, then switch back to your branch
#
# Day to day you commit on dev/<name> as usual. 'main' is guarded by a pre-commit
# hook (.githooks/pre-commit), so only 'promote' (or ALLOW_MAIN=1) can write to it.
set -euo pipefail

die() { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
has_remote() { git remote get-url origin >/dev/null 2>&1; }
slug() { printf '%s' "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-'; }

cmd="${1:-}"; shift || true

case "$cmd" in
  init)
    [[ -n "${1:-}" ]] || die "Usage: branch.sh init <your-name>"
    name="$(slug "$1")"
    git branch -M main
    if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
      say "No commits yet - creating the initial scaffold commit on main"
      git add -A
      ALLOW_MAIN=1 git commit -m "Initial project scaffold"
    fi
    git switch -c "dev/$name"
    say "You're on dev/$name. Commit here freely."
    has_remote || echo "   (No remote yet. Colleagues need one: git remote add origin <url> && git push -u origin main dev/$name)"
    ;;

  start)
    [[ -n "${1:-}" ]] || die "Usage: branch.sh start <name>"
    name="$(slug "$1")"
    has_remote && git fetch origin
    base="main"
    has_remote && git rev-parse --verify origin/main >/dev/null 2>&1 && base="origin/main"
    git switch -c "dev/$name" "$base"
    say "On dev/$name (from $base)."
    ;;

  sync)
    cur="$(git symbolic-ref --short HEAD)"
    [[ "$cur" != "main" ]] || die "Switch to your dev branch first."
    [[ -z "$(git status --porcelain)" ]] || die "Commit or stash your changes first."
    if has_remote; then git fetch origin; git merge --no-edit origin/main; else git merge --no-edit main; fi
    ;;

  promote)
    msg=""
    while [[ "${1:-}" == -* ]]; do
      case "$1" in
        -m) msg="${2:-}"; shift 2 ;;
        *)  die "Unknown option: $1" ;;
      esac
    done
    [[ $# -gt 0 ]] || die "Usage: branch.sh promote [-m \"msg\"] <paths...>"
    src="$(git symbolic-ref --short HEAD)"
    [[ "$src" != "main" ]] || die "Run this from your dev branch, not main."
    [[ -z "$(git status --porcelain)" ]] || die "Commit or stash your changes on $src first."

    git switch main
    back() { git switch "$src" >/dev/null 2>&1 || true; }
    trap back EXIT

    git restore --source="$src" --staged --worktree -- "$@"
    if git diff --cached --quiet; then
      say "Nothing to promote: those paths already match main."
      exit 0
    fi
    git diff --cached --stat
    ALLOW_MAIN=1 git commit -m "${msg:-Promote selected files from $src}"
    say "Committed on main. Back on $src.  (Nothing was pushed.)"
    ;;

  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
