#!/usr/bin/env bash
# One-time bootstrap for the open-source ASIC project (macOS).
# Safe to re-run: every step checks before it installs or writes anything.
#
#   ./scripts/setup.sh            # set everything up
#   ./scripts/setup.sh --smoke    # ...and run the flow's built-in smoke test (pulls Docker image + PDK)
#
# Env overrides:  PYTHON=python3.13   FLOW_PKG=openlane   (default flow package: librelane)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
FLOW_PKG="${FLOW_PKG:-librelane}"   # LibreLane = maintained successor of OpenLane 2 (same config format)
SMOKE=0
[[ "${1:-}" == "--smoke" ]] && SMOKE=1

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run 'git init' in the project root first."
have brew || die "Homebrew not found. Install it from https://brew.sh and re-run."

# ---------------------------------------------------------------- 1. CLI tools
say "Checking Homebrew packages"
for pkg in git direnv yosys verilator icarus-verilog ngspice; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    echo "   ok  $pkg"
  else
    say "Installing $pkg"
    brew install "$pkg"
  fi
done

# GUI apps: only warn, never auto-install (you already have most of these)
have gtkwave || [[ -d /Applications/gtkwave.app ]] || warn "GTKWave not found (brew install --cask gtkwave, or use Surfer)"
[[ -d /Applications/klayout.app || -d /Applications/KLayout ]] || warn "KLayout not found (https://www.klayout.de)"
have docker || [[ -d /Applications/Docker.app ]] || warn "Docker Desktop not found (https://www.docker.com/products/docker-desktop)"

# ------------------------------------------------- 2. Python venv + flow package
# A venv is required: Homebrew's Python refuses global 'pip install' (PEP 668).
if [[ ! -x .venv/bin/python ]]; then
  say "Creating .venv with $($PYTHON --version)"
  "$PYTHON" -m venv .venv
fi
say "Installing $FLOW_PKG + cocotb into .venv"
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet --upgrade "$FLOW_PKG" cocotb

# ----------------------------------------------------- 3. Folder layout in git
say "Making sure the standard folders exist (and are tracked by git)"
for d in workspace source_code/rtl source_code/tb inputs libraries scripts apps reports export docs; do
  mkdir -p "$d"
  [[ -z "$(ls -A "$d")" ]] && touch "$d/.gitkeep"
done

# ---------------------------------------------------------------- 4. .gitignore
add_ignore() { grep -qxF "$1" .gitignore 2>/dev/null || echo "$1" >> .gitignore; }
touch .gitignore
for pat in ".venv/" ".direnv/" "runs/" "__pycache__/" "sim_build/" "*.vcd" ".DS_Store" "export/*/" "reports/*/"; do
  add_ignore "$pat"
done

# ------------------------------------------- 5. direnv: auto-environment on cd
if [[ ! -f .envrc ]]; then
  say "Writing .envrc"
  cat > .envrc <<'EOF'
# Loaded automatically by direnv whenever you cd into this project.
export PROJECT_ROOT="$PWD"
export VIRTUAL_ENV="$PWD/.venv"
PATH_add .venv/bin
PATH_add scripts
EOF
fi
if ! grep -qs 'direnv hook zsh' "$HOME/.zshrc"; then
  say "Adding direnv hook to ~/.zshrc"
  printf '\n# direnv\neval "$(direnv hook zsh)"\n' >> "$HOME/.zshrc"
  warn "Open a new terminal tab (or: source ~/.zshrc) so the hook is active."
fi
direnv allow . >/dev/null 2>&1 || true

# ------------------------------------- 6. Guard: no accidental commits to main
mkdir -p .githooks
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# Blocks commits on 'main' unless you opt in with ALLOW_MAIN=1 (scripts/branch.sh does this for you).
branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
if [[ "$branch" == "main" && "${ALLOW_MAIN:-0}" != "1" ]]; then
  echo "Commit blocked: you're on main. Work on your dev/<name> branch."
  echo "To put chosen files on main on purpose:  scripts/branch.sh promote -m \"msg\" <paths...>"
  exit 1
fi
EOF
chmod +x .githooks/pre-commit scripts/*.sh 2>/dev/null || true
git config core.hooksPath .githooks

# ------------------------------------------------------ 7. starter config.json
if [[ ! -f config.json ]]; then
  say "Writing starter config.json (edit DESIGN_NAME / CLOCK_PORT)"
  cat > config.json <<'EOF'
{
  "DESIGN_NAME": "your_top_module",
  "VERILOG_FILES": "dir::source_code/rtl/*.v",
  "CLOCK_PORT": "clk",
  "CLOCK_PERIOD": 10.0,
  "PDK": "sky130A"
}
EOF
fi

# ------------------------------------------------------------ 8. optional smoke
if [[ $SMOKE -eq 1 ]]; then
  say "Running smoke test (first run downloads the container image and the PDK)"
  "$ROOT/scripts/run_flow.sh" --smoke-test
fi

say "Done. Next:  scripts/branch.sh init <your-name>   (creates main + your dev branch)"
