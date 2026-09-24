"""install-skill — register the ``research`` agent skill so harnesses auto-discover it.

WHAT this does: brings ``research install-skill`` to PARITY with the sibling personal CLIs
(draw/tg/review/task), whose installers each write THREE idempotent layers — not just a
SKILL.md:

1. **SKILL.md + blurb + compat symlink.** ``~/.agents/skills/research/SKILL.md`` (Agent Skills
   standard) so Claude Code / Codex / opencode / Gemini / Cursor surface ``research`` as a
   capability, plus the one-line ``~/.agents/skills/.blurbs/research.md`` (the always-on
   advertisement a SessionStart hook cats into every session), plus a
   ``~/.claude/skills/research`` symlink (Claude Code also scans that dir).
2. **A marked block in each detected harness's instruction file.** A
   ``<!-- skill:research -->…<!-- /skill:research -->`` block is written into the instruction
   file of each harness DETECTED on this machine. The block is REPLACED on re-run (never
   duplicated); nothing else in the file is touched.
3. **An idempotent SessionStart aggregator hook** in ``~/.claude/settings.json`` that cats every
   ``.blurbs/*.md`` into each new Claude Code session.

Stdlib-only; every write is idempotent (skips an already-current target, replaces — never
duplicates — a marked block, and won't re-add an existing hook). The block/hook plumbing mirrors
the sibling installers byte-for-byte so a machine advertises ``research`` exactly where it
advertises draw/tg/review/task.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

SKILL_NAME = "research"
SKILL_MD = """\
---
name: research
description: >-
  Multi-provider research/panel CLI. Put a question to a PANEL of models (each through
  a lens — analyst/skeptic/scout), then synthesize one attributed note. Distinct from
  review-cli (research, not code review). Commands: `research ask "<question>"`,
  `--offline`, `--json`, `research board`.
metadata:
  author: alex-mextner
  repo: https://git.hyperide.ai/ultrabricks/research-cli
---

# research — multi-provider research / panel

You ask a question; it asks a panel of different models, each through a research lens, then
synthesizes their answers into one attributed Markdown note (deterministic, offline synthesis —
never itself a hallucination).

## Commands
```
research ask "<question>"        # single-round multi-provider panel pass + synthesis
research ask --offline "..."      # run the whole pipeline with no key (stub transport)
research ask --json "..."         # emit a machine-readable JSON object instead of the note
research board                    # show the panel resolved against the shared model manifest
research --help                   # full usage
```

## Key facts
- **Distinct from review-cli**: research lenses (broad analyst / skeptic / fast scout), not
  code-review lenses. Same providers engine, different product.
- **Reachability via the shared key cascade**: a seat is reachable iff its provider's API key
  resolves (env vars first, then `.env`). With no key for any seat, `research ask` prints an
  empty-panel note and exits `7` (the shared NETWORK class) — it never crashes.
- **Live backend (MVP)**: set `RESEARCH_BACKEND_CMD` to a shell template receiving
  `{model} {lens} {question}` that prints the answer to stdout. Without it, run `--offline`.
- **Structured exit codes** (shared agenttools-errors contract): `0` ok, `2` usage/bad manifest,
  `4` unknown command, `7` nothing reachable/answered.
"""

# One-line SessionStart blurb, same shape the siblings (draw/tg/review/task) use. The hook cats
# every ``.blurbs/*.md`` verbatim, so keep this a single bullet line ending in a newline.
BLURB = (
    "- `research` — multi-provider research/panel CLI. Put a question to a PANEL of different "
    "models (analyst/skeptic/scout lenses) and synthesize one attributed note. DISTINCT from "
    "review-cli (research, not code review). `research ask \"<q>\"`, `research ask --offline`, "
    "`research ask --json`, `research board`. No key → empty-panel note + exit 7, never crashes.\n"
)


# The SessionStart aggregator that cats every installed tool's blurb into a new session. The
# marker (a trailing shell comment) makes the hook self-identifying so re-installs never add a
# second copy; it matches the shape rig + the sibling installers already use on this machine.
_HOOK_MARKER = "# agent-tools-awareness"
_HOOK_COMMAND = (
    'sh -c \'d="$HOME/.agents/skills/.blurbs"; ls "$d"/*.md >/dev/null 2>&1 && '
    '{ printf "Agent CLI tools installed on this machine (prefer them):\\n"; '
    'cat "$d"/*.md; }\' ' + _HOOK_MARKER
)

# The harness instruction files this installer injects the marked blurb-block into — but ONLY
# when the harness is detected on this machine (its config dir exists). Keep in step with the
# siblings (tg/review/draw/task) so a machine advertises `research` exactly where it advertises them.
_HARNESSES: tuple[tuple[str, str], ...] = (
    (".claude", "CLAUDE.md"),
    (".codex", "AGENTS.md"),
    (".config/opencode", "AGENTS.md"),
    (".gemini", "GEMINI.md"),
)


def _home() -> Path:
    return Path(os.environ.get("HOME") or os.path.expanduser("~"))


def _write_if_changed(target: Path, content: str) -> bool:
    """Write ``content`` to ``target`` unless it is already current. Returns True on write."""
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file() and target.read_text(encoding="utf-8") == content:
        print(f"research: already current at {target}")
        return False
    target.write_text(content, encoding="utf-8")
    print(f"research: wrote {target}")
    return True


def _ensure_claude_skills_symlink(home: Path) -> None:
    """Symlink ``~/.claude/skills/research`` → the canonical skill dir (Claude Code scans both).

    Only when ``~/.claude/skills`` already exists. A pre-existing link/file is left as-is; a
    symlink failure (unsupported FS / race) is non-fatal — the canonical ``~/.agents`` copy is
    what matters.
    """
    claude_skills = home / ".claude" / "skills"
    if not claude_skills.is_dir():
        return
    link = claude_skills / SKILL_NAME
    if link.exists() or link.is_symlink():
        return
    try:
        link.symlink_to(home / ".agents" / "skills" / SKILL_NAME)
        print(f"research: linked {link}")
    except OSError:
        pass  # symlink unsupported or a race — the ~/.agents copy still advertises the skill


def _blurb_block(blurb: str) -> str:
    """The marked block written into a harness instruction file (replaced wholesale on re-run)."""
    return f"<!-- skill:{SKILL_NAME} -->\n{blurb.rstrip()}\n<!-- /skill:{SKILL_NAME} -->\n"


def _inject_marked_block(path: Path, blurb: str) -> None:
    """Insert (or refresh IN PLACE) the ``<!-- skill:research -->…`` block in ``path``."""
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.is_file() else ""
    new_text = _replace_or_append_block(existing, _blurb_block(blurb))
    if path.is_file() and existing == new_text:
        print(f"research: already current at {path}")
        return
    path.write_text(new_text, encoding="utf-8")
    print(f"research: advertised in {path}")


def _replace_or_append_block(existing: str, block: str) -> str:
    """Return ``existing`` with our marked block refreshed in place, or appended if absent.

    Pure (no I/O) so the order-preserving behavior is unit-testable. When a well-formed
    ``<!-- skill:research -->…<!-- /skill:research -->`` pair exists, ONLY that exact pair is
    swapped for ``block`` at the same offset; everything around it is preserved. We anchor on the
    FIRST close marker and the LAST open marker BEFORE it, so a stray earlier open marker is
    treated as an orphan (stripped, surrounding text kept), not as the block's opening.
    """
    start, end = f"<!-- skill:{SKILL_NAME} -->", f"<!-- /skill:{SKILL_NAME} -->"
    e_idx = existing.find(end)
    s_idx = existing.rfind(start, 0, e_idx) if e_idx != -1 else -1
    if e_idx != -1 and s_idx != -1:
        block_end = e_idx + len(end)
        if block_end < len(existing) and existing[block_end] == "\n":
            block_end += 1  # consume the block's own trailing newline so we don't double it
        rebuilt = existing[:s_idx] + block + existing[block_end:]
        return _strip_stray_markers(rebuilt, (start, end), protect=(s_idx, s_idx + len(block)))
    existing = _strip_stray_markers(existing, (start, end), protect=None)
    body = existing.rstrip()
    return f"{body}\n\n{block}" if body else block


def _strip_stray_markers(
    text: str, markers: tuple[str, ...], *, protect: tuple[int, int] | None
) -> str:
    """Remove every stray skill-marker token (each of ``markers``) from ``text``, keeping all other
    text. Stripping BOTH the open and close markers symmetrically keeps the refresh idempotent.

    ``protect`` is a ``(lo, hi)`` byte span (the freshly-inserted block) whose markers are left
    intact. Only the token is removed (not its line), so user text sharing a line with a stray
    marker survives.
    """
    spans: list[tuple[int, int]] = []
    for marker in markers:
        i = 0
        while True:
            j = text.find(marker, i)
            if j == -1:
                break
            spans.append((j, j + len(marker)))
            i = j + len(marker)
    out: list[str] = []
    cursor = 0
    for lo, hi in sorted(spans):
        if lo < cursor:
            continue  # overlapping match already consumed
        if protect is not None and protect[0] <= lo < protect[1]:
            continue  # keep the protected (real-block) marker
        out.append(text[cursor:lo])  # keep text before the stray token, drop the token itself
        cursor = hi
    out.append(text[cursor:])
    return "".join(out)


def _inject_into_detected_harnesses(home: Path, blurb: str) -> None:
    """Inject the marked blurb-block into each detected harness's instruction file."""
    for config_dir, instruction_file in _HARNESSES:
        if (home / config_dir).is_dir():
            _inject_marked_block(home / config_dir / instruction_file, blurb)


def _hook_already_present(session_start: list) -> bool:
    """True if a SessionStart hook carrying our marker is already registered."""
    for group in session_start:
        hooks = group.get("hooks") if isinstance(group, dict) else None
        if not isinstance(hooks, list):
            continue
        for hook in hooks:
            cmd = hook.get("command") if isinstance(hook, dict) else None
            if isinstance(cmd, str) and _HOOK_MARKER in cmd:
                return True
    return False


def _ensure_session_start_hook(home: Path) -> None:
    """Add the SessionStart blurb-aggregator hook to ``~/.claude/settings.json``, idempotently.

    Conservative by design: only when ``~/.claude`` exists; a missing settings file is created
    with just the hook; an UNPARSEABLE settings file is left untouched (never clobbered); and an
    already-present hook (matched by its marker) is a no-op. We back up the file before rewriting.
    """
    if not (home / ".claude").is_dir():
        return
    settings_path = home / ".claude" / "settings.json"
    original = settings_path.read_text(encoding="utf-8") if settings_path.is_file() else None
    try:
        data = json.loads(original) if original is not None else {}
    except ValueError:
        print(f"research: WARNING — {settings_path} is not valid JSON; skipping the SessionStart hook")
        return
    if not isinstance(data, dict):
        print(f"research: WARNING — {settings_path} is not a JSON object; skipping the SessionStart hook")
        return

    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        print(f"research: WARNING — {settings_path} has a non-object 'hooks'; skipping the hook")
        return
    session_start = hooks.setdefault("SessionStart", [])
    if not isinstance(session_start, list):
        print(f"research: WARNING — {settings_path} has a non-list 'SessionStart'; skipping the hook")
        return
    if _hook_already_present(session_start):
        print(f"research: SessionStart hook already present in {settings_path}")
        return

    session_start.append({"hooks": [{"type": "command", "command": _HOOK_COMMAND}]})
    if original is not None:
        backup = settings_path.parent / "settings.json.bak"
        if not (backup.exists() or backup.is_symlink()):
            backup.write_text(original, encoding="utf-8")
    _atomic_write(settings_path, json.dumps(data, indent=2) + "\n")
    print(f"research: added SessionStart blurb-aggregator hook to {settings_path}")


def _atomic_write(target: Path, content: str) -> None:
    """Write ``content`` to ``target`` via a temp file + rename, so a crash can't truncate it."""
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    os.replace(tmp, target)


def install_skill() -> int:
    """Install all three advertisement layers (idempotent). See the module docstring."""
    home = _home()
    skills_root = home / ".agents" / "skills"

    # Layer 1 — SKILL.md + always-on blurb + the Claude-Code compat symlink.
    _write_if_changed(skills_root / SKILL_NAME / "SKILL.md", SKILL_MD)
    _write_if_changed(skills_root / ".blurbs" / f"{SKILL_NAME}.md", BLURB)
    _ensure_claude_skills_symlink(home)

    # Layer 2 — a marked blurb-block in each detected harness instruction file.
    _inject_into_detected_harnesses(home, BLURB)

    # Layer 3 — the SessionStart aggregator hook (Claude Code).
    _ensure_session_start_hook(home)
    return 0
