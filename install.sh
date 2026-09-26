#!/usr/bin/env bash
# install.sh — install the `research` CLI (Python 3).
# Works from a local clone (./install.sh) and piped from curl:
#   curl -fsSL https://git.hyperide.ai/ultrabricks/research-cli/raw/branch/main/install.sh | bash
set -euo pipefail

# ── identity ──────────────────────────────────────────────────────────────────
TOOL="research"
REPO="research-cli"
FORGE="https://git.hyperide.ai/ultrabricks"   # canonical home; github.com/alex-mextner is an archived mirror
ENTRY="bin/research"   # path inside repo root
CLONE_BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
EXPECT_URL="$FORGE/$REPO.git"
DIST="hyper-research"   # PyPI distribution name
UV_WITH="pyyaml"   # optional dep the Windows uv install adds (pyproject extra)

# ── Windows (Cygwin / MSYS2 / Git Bash) ───────────────────────────────────────
# There python, git and uv are native Windows programs: a symlink to the entry script (a
# `#!/usr/bin/env python3` file) cannot run, and Cygwin's own ~/.local/bin is not the one on
# PATH. `uv tool install` puts a real <tool>.exe into %USERPROFILE%\.local\bin, which IS on PATH
# in every Windows shell — so on Windows that is the whole install.
case "$(uname -s)" in
  CYGWIN*|MINGW*|MSYS*)
    if ! command -v uv >/dev/null 2>&1; then
      echo "ERROR: on Windows $TOOL installs through uv, and uv is not on PATH." >&2
      echo "       Install it:  winget install astral-sh.uv   (or: powershell -c \"irm https://astral.sh/uv/install.ps1 | iex\")" >&2
      exit 1
    fi
    _with=(); [[ -n "${UV_WITH:-}" ]] && _with=(--with "$UV_WITH")  # one argument, spaces and all
    _here=""
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
      _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    if [[ -n "$_here" && -f "$_here/$ENTRY" ]]; then
      _src="$_here"; command -v cygpath >/dev/null 2>&1 && _src="$(cygpath -w "$_here")"
      echo "$TOOL: Windows — uv tool install --editable $_src"
      uv tool install --force --editable "$_src" ${_with[@]+"${_with[@]}"}
    else
      echo "$TOOL: Windows — uv tool install git+${EXPECT_URL%.git}"
      uv tool install --force "git+${EXPECT_URL%.git}" ${_with[@]+"${_with[@]}"}
    fi
    _bindir="$(uv tool dir --bin 2>/dev/null || true)"
    if [[ -n "$_bindir" ]] && command -v cygpath >/dev/null 2>&1; then _bindir="$(cygpath -u "$_bindir")"; fi
    if [[ -n "$_bindir" && ":$PATH:" != *":$_bindir:"* ]]; then
      echo ""
      echo "  NOTE: $_bindir (where uv put $TOOL.exe) is not on PATH — run 'uv tool update-shell'"
      echo "        or add it to PATH, then open a new shell."
    fi
    PYTHONUTF8=1 "${_bindir:+$_bindir/}$TOOL" install-skill \
      || echo "  WARNING: '$TOOL install-skill' failed — re-run it once $TOOL is on PATH."
    echo ""
    if [[ -n "${_src:-}" ]]; then _upd="git pull in $_here"; else _upd="uv tool upgrade $DIST"; fi
    echo "  $TOOL is installed (uv tool). Update: $_upd"
    exit 0
    ;;
esac

# Origins that are the same repo: the canonical Forgejo one and the pre-migration GitHub ones (a
# GitHub origin is re-pointed at Forgejo — the GitHub copy is frozen). Compared as HOST + PATH, never
# as a substring: an origin that merely contains "hyperide.ai" (git.hyperide.ai.evil.example,
# evil.example/git.hyperide.ai/…) must not pass for the canonical repo and get pulled + installed.
_url_host_path() {  # https / ssh / scp-style git URL -> "host path" (user@, :port, .git, trailing / dropped)
  local _u _hp _path _host
  _u=${1%/}; _u=${_u%.git}
  case "$_u" in
    https://*|ssh://*) _u=${_u#*://}; _hp=${_u%%/*}; _path=${_u#*/} ;;
    *@*:*) _hp=${_u%%:*}; _path=${_u#*:} ;;
    *) return 1 ;;
  esac
  [ "$_path" != "$_u" ] || return 1
  _host=${_hp##*@}; _host=${_host%%:*}
  printf '%s %s\n' "$_host" "$_path"
}
_origin_is_canonical() {
  [ "$(_url_host_path "$1")" = "git.hyperide.ai ultrabricks/$REPO" ]
}
_origin_is_legacy() {
  case "$(_url_host_path "$1")" in
    "github.com alex-mextner/$REPO"|"github.com ultrabricks/$REPO") return 0 ;;
  esac
  return 1
}

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
  if [[ -d "$CLONE_DIR/.git" ]]; then
    actual_url="$(git -C "$CLONE_DIR" remote get-url origin 2>/dev/null || echo "")"
    if _origin_is_legacy "$actual_url"; then
      echo "research: $REPO moved to $FORGE — re-pointing origin ($actual_url -> $EXPECT_URL)"
      git -C "$CLONE_DIR" remote set-url origin "$EXPECT_URL"
    elif ! _origin_is_canonical "$actual_url"; then
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
