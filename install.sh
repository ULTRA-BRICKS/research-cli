#!/usr/bin/env bash
# install.sh — install the `research` CLI (Python 3).
# Works from a local clone (./install.sh) and piped from curl:
#   curl -fsSL https://git.hyperide.ai/ultrabricks/research-cli/raw/branch/main/install.sh | bash
set -euo pipefail

# ── identity ──────────────────────────────────────────────────────────────────
TOOL="research"
REPO="research-cli"
ORG="ultrabricks"
ENTRY="bin/research"   # path inside repo root
CLONE_BASE="${XDG_DATA_HOME:-$HOME/.local/share}"

# ── locate source dir ─────────────────────────────────────────────────────────
_script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$_script_dir" && -f "$_script_dir/$ENTRY" ]]; then
  SRC="$_script_dir"
  echo "research: using local clone at $SRC"
else
  mkdir -p "$CLONE_BASE"
  CLONE_DIR="$CLONE_BASE/$REPO"
  EXPECT_URL="https://git.hyperide.ai/$ORG/$REPO.git"
  if [[ -d "$CLONE_DIR/.git" ]]; then
    actual_url="$(git -C "$CLONE_DIR" remote get-url origin 2>/dev/null || echo "")"
    if [[ "$actual_url" != "$EXPECT_URL" ]]; then
      echo "ERROR: $CLONE_DIR exists but its origin is '$actual_url', not $EXPECT_URL." >&2
      echo "       Remove that directory or fix its remote, then re-run." >&2
      exit 1
    fi
    echo "research: updating existing clone at $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only
  else
    echo "research: cloning $EXPECT_URL into $CLONE_DIR"
    git clone "$EXPECT_URL" "$CLONE_DIR"
  fi
  SRC="$CLONE_DIR"
fi

# ── bin dir ───────────────────────────────────────────────────────────────────
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

if [[ ":$PATH:" != *":$BIN:"* ]]; then
  echo ""
  echo "  NOTE: $BIN is not on your PATH."
  echo "  Add this to your ~/.bashrc or ~/.zshrc and restart your shell:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
fi

# ── dependency: pyyaml (models.yaml manifest parse) ────────────────────────────
# The CLI degrades gracefully without it (a manifest read errors with an actionable hint),
# but `research board` / `research ask` against the default manifest need it.
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "research: pyyaml not found, attempting: python3 -m pip install --user pyyaml"
  if ! python3 -m pip install --user pyyaml 2>/dev/null; then
    echo ""
    echo "  WARNING: could not install pyyaml. Reading the models manifest needs it; the tool"
    echo "  prints an actionable error until it is present. Install manually: pip install --user pyyaml"
    echo ""
  fi
fi

# ── symlink entry ─────────────────────────────────────────────────────────────
ENTRY_PATH="$SRC/$ENTRY"
chmod +x "$ENTRY_PATH"
ln -sfn "$ENTRY_PATH" "$BIN/$TOOL"
echo "research: symlinked $BIN/$TOOL -> $ENTRY_PATH"

# ── register skill ────────────────────────────────────────────────────────────
if ! "$BIN/$TOOL" install-skill; then
  echo "  WARNING: '$TOOL install-skill' failed — $TOOL is installed but agents may not"
  echo "           auto-discover it. Re-run '$TOOL install-skill' manually to fix."
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  research is installed."
echo ""
echo "  Usage: research ask \"<question>\"        — single-round multi-provider panel pass"
echo "         research ask --offline \"...\"       — run with no key (stub transport)"
echo "         research ask --json \"...\"          — machine-readable JSON output"
echo "         research board                      — show the resolved research board"
echo "         research --help                     — full usage"
echo ""
echo "  A live backend (MVP) is wired via RESEARCH_BACKEND_CMD (a shell template receiving"
echo "  {model} {lens} {question}); without it, use --offline."
echo ""
