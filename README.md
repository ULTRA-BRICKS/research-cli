# research-cli

A multi-provider **research / panel** CLI built on the shared `agenttools_providers`
engine. You ask a question; it puts that question to a *panel* of different models, each
through a research lens, then synthesizes their answers into one attributed note.

It is a **distinct tool, not a review-cli mode.** Code review and research are different
products; bolting research onto review as a mode would conflate them. But research needs
the *exact same* multi-model plumbing review-cli uses — board, failover, key cascade,
capability tags — which is why it **reuses verbatim** the shared providers CORE.

```sh
research ask "What are the real trade-offs of a monorepo at 200 engineers?"
research board          # show the panel resolved against the shared model manifest
research ask --offline "…"   # run the whole pipeline with no key (stub transport)
research ask --json "…"      # emit a machine-readable JSON object instead of the note
```

## Install

Pick one — each ends with `research` on your PATH:

```bash
# 1. uv — recommended; macOS, Linux and Windows (incl. Cygwin / Git Bash)
uv tool install 'research-cli[yaml] @ git+https://git.hyperide.ai/ultrabricks/research-cli'

# 2. pipx
pipx install 'research-cli[yaml] @ git+https://git.hyperide.ai/ultrabricks/research-cli'

# 3. one-liner — clones to ~/.local/share/research-cli, links research into ~/.local/bin, registers the agent skill
curl -fsSL https://git.hyperide.ai/ultrabricks/research-cli/raw/branch/main/install.sh | bash

# 4. from a clone — to hack on it; `git pull` updates the installed tool
git clone https://git.hyperide.ai/ultrabricks/research-cli && cd research-cli && ./install.sh
```

- After **1** or **2**, run `research install-skill` once so coding agents discover `research` (3 and 4 do it for you).
- **Update:** `uv tool upgrade research-cli` · `pipx upgrade research-cli` · re-run the one-liner · `git pull`.
- **Via rig:** clone into `~/xp/research-cli` and list `research` under `tools.items` in `~/.config/rig/config.yaml` — `rig apply commit` runs its `install.sh` and keeps the clone fresh.
- **Windows:** use uv (option 1) — `./install.sh` and the one-liner do exactly that under Cygwin / Git Bash. If a command dies with `UnicodeEncodeError` in mintty, run `setx PYTHONUTF8 1` once. More: [rig-cli → Windows](https://git.hyperide.ai/ultrabricks/rig-cli#windows-cygwin-git-bash-powershell).

> **Not on PyPI — always install from the git URL.** A bare `pipx install research-cli` /
> `uv tool install research-cli` does not install this tool: the name is unclaimed on PyPI or (for
> `rig-cli`, `dev-cli`, `harness-cli`) belongs to an unrelated project. The canonical repo is
> **git.hyperide.ai/ultrabricks/research-cli**; `github.com/alex-mextner/research-cli` is a frozen,
> archived mirror.

Or run straight from the checkout (no install step — the entry point and the package shims
put the package + the vendored libs on `sys.path`):

```sh
./bin/research ask --offline "…"
```

Or install as a package (editable keeps the checkout, so the vendored manifest resolves):

```sh
pip install -e '.[yaml]'
research ask "…"
```

PyYAML is needed only to read a `models.yaml` manifest (the default board path); the CORE
imports it lazily, so `--help` / `--version` and an in-memory registry never need it.

## Vendored shared libraries (single-source via a drift guard)

research-cli was spun out of the `agent-tools` umbrella ([research-cli#1](https://git.hyperide.ai/ultrabricks/research-cli/issues/1)).
It depends on three shared things that are **not on PyPI**:

| Vendored under `vendor/` | Canonical source in agent-tools |
| --- | --- |
| `agenttools_providers/` (the providers CORE) | `lib/agenttools_providers/` |
| `agenttools_errors/` (the structured-error layer) | `lib/agenttools_errors/` |
| `contracts/models.yaml` (the shared model manifest) | `lib/contracts/models.yaml` |

Rather than depend on a PyPI publish (**strategy A** — deferred; it needs a PyPI account),
this repo **vendors** them (**strategy B**, the proven task-cli pattern) and keeps them
single-source via a **pinned-SHA drift guard**:

- Each vendored file carries a `# SYNC-HEADER … #` block with a pinned `CANONICAL_SHA256` +
  the agent-tools commit it came from — the **only** delta from the canonical body.
- `tests/test_vendored_libs_sync.py` reconstructs each canonical body (header stripped) and
  asserts its SHA256 matches the pin — a local edit or a stale copy **fails CI**.
- `.github/workflows/vendored-libs-drift.yml` runs the same script in `--check` mode against
  the **live** agent-tools canonical weekly, and opens/updates a tracking issue on upstream
  drift (which the pinned-SHA test alone can't see).

To re-sync after an intentional canonical change in agent-tools:

```sh
python scripts/resync_vendored_libs.py /path/to/agent-tools   # re-copies bodies + bumps the pins
```

> **When agenttools-providers / agenttools-errors are published to PyPI**, the vendored
> copies can be swapped for declared caret-range dependencies in `pyproject.toml` and the
> `vendor/` `sys.path` shims dropped. The drift guard is the bridge until then.

## What it reuses vs what it adds

The shared `agenttools_providers` CORE is deliberately **network-free**: it decides
*which* seat / key to use; the consuming tool owns *how* to reach it. research-cli is that
consuming tool.

| Concern | Where it lives |
| --- | --- |
| Capability-tagged model **registry** + **role resolution** (`resolve_role`) | **reused** from `agenttools_providers` |
| Priority-ordered failover **Board** + pool/reserve split (`Board.split`) | **reused** from `agenttools_providers` |
| **Key cascade** (env beats `.env`, name precedence beats file order) | **reused** from `agenttools_providers` |
| Capability-tag **filtering** (`with_capability`) | **reused** from `agenttools_providers` |
| The shared **manifest** (`models.yaml`) | **reused** (vendored) — not forked |
| The **transport** (reachability predicate + the live call) | **added** here (`research_cli/transport.py`) |
| The **research board** (analyst / skeptic / scout lenses) | **added** here — research lenses |
| The **panel pass** + synthesis | **added** here (`research_cli/engine.py`) |

The transport layer is behind a small `Transport` protocol, so the panel engine is fully
unit-testable with an injected stub — no network in any test.

## Architecture

```
bin/research                     # entry point -> research_cli.cli:main
research_cli/
  cli.py                         # self-registering command dispatcher (drop a file = a command)
  providers.py                   # the "reuse providers verbatim" bridge (imports the vendored CORE)
  transport.py                   # the DEFERRED half: reachability + the live call (Stub + Subprocess)
  engine.py                      # the single-round panel pass + deterministic synthesis (MVP)
  install.py                     # `research install-skill` — the 3-layer agent-skill installer
  commands/
    ask.py                       # research ask "<question>"  — the panel pass
    board.py                     # research board             — show the resolved board
    install_skill.py             # research install-skill     — register the agent skill
vendor/                          # vendored agent-tools libs + manifest (see above; do not edit)
scripts/resync_vendored_libs.py  # the drift guard (--check) + re-sync
```

Commands **self-register**: drop a `commands/<name>.py` exposing `NAME`, `SUMMARY`, and
`run(argv) -> int`, and it becomes `research <name>` with zero edits to the dispatcher.

## How a run works (single round — the MVP)

1. Resolve the failover **Board** against the shared registry (CORE `resolve_role`).
2. Use the transport's reachability as the CORE Board's availability **predicate**, so
   `board.split(pool, predicate)` returns the top-N reachable seats + a reserve. A seat
   unreachable at startup (no key for its provider) is **skipped** and the next-priority
   one **promoted**.
3. Ask each pooled seat the question through its lens. If a pooled seat **fails at call
   time**, the next reserve seat backfills it (mid-run failover).
4. **Synthesize** the answers into one Markdown note, each answer attributed to its
   concrete model + lens, with a footer noting how many answered and who was unavailable.

The MVP synthesis is **deterministic and offline** (a structured layout, not a model
call), so the output is testable and never itself a hallucination.

## Output formats

By default `research ask` prints the Markdown synthesis note. Pass `--json` to get a
stable, machine-readable object instead. The same structured **exit-code** contract applies
under `--json`: when no seat answers, the JSON object is still printed first (with
`answered: 0`) and the command still exits `7` (`EXIT_NETWORK`).

## Reachability and keys

A seat is reachable iff its provider's API key resolves through the shared **key cascade**
(env vars first, in name order, then `.env` files). The provider → key-name map is in
`research_cli/providers.py` (`PROVIDER_KEY_NAMES`). With no key for any seat, `research
ask` prints an empty-panel note and exits `7` — it never crashes.

To wire a **live** backend for the MVP, set `RESEARCH_BACKEND_CMD` to a shell template that
receives `{model}`, `{lens}`, `{question}` and prints the answer to stdout, e.g.:

```sh
export RESEARCH_BACKEND_CMD='opencode run --model {model} {question}'
research ask "…"
```

## Exit codes (structured)

research-cli uses the shared **`agenttools_errors`** contract (error-system v2): a diagnosed
failure prints a three-part **what / why / how-to-fix** block and exits with a stable
per-class code, the same contract every ecosystem CLI (rig / review / …) uses.

| Code | Class | Meaning |
| --- | --- | --- |
| `0` | `EXIT_OK` | a synthesis was produced (≥1 seat answered) |
| `1` | `EXIT_INTERNAL` | an internal bug (an uncaught exception) |
| `2` | `EXIT_USAGE` | usage/config error: no question, a bad flag, or a malformed/missing manifest |
| `4` | `EXIT_UNKNOWN_ITEM` | an unknown command (with a did-you-mean suggestion) |
| `7` | `EXIT_NETWORK` | no seat reachable / answered (no key, no backend, offline) |

## Tests

```sh
pip install -e '.[test]'
python -m pytest -q
```

Every test is deterministic and network-free: the transport is the network seam, so the
panel engine is driven by an injected `StubTransport`. Coverage: the providers-engine reuse,
transport reachability + the live shell-out path, the full single-round panel pass (pool
sizing, startup skip-and-promote, mid-run failover backfill, empty-panel), the synthesis +
JSON formatting, the CLI dispatcher + `ask`/`board` commands, the shared-error surface, and
the **vendored-libs drift guard**. (The `install-skill` file-mutation helpers in
`research_cli/install.py` are not yet unit-tested — tracked in
[#3](https://git.hyperide.ai/ultrabricks/research-cli/issues/3).)

## Roadmap (the phased rest)

The MVP is a single round + a deterministic synthesis. Deferred, in priority order:

1. **A real transport** — the `oc:` / `opencode:` provider router, `api|cli` mode selection,
   response parsing, timeouts, sidecar logging.
2. **Multi-round** research — feed the round-1 synthesis back as follow-up questions.
3. **Adversarial cross-examination** — seats critique each other's answers before synthesis.
4. **Citation / source verification** — fetch and check cited sources; flag unsupported claims.
5. **Model-driven synthesis** — optionally ask a strong seat to reconcile the panel.

## License

MIT.

<!-- rig:ecosystem-block -->
## Ecosystem

Part of the [HyperIDE.ai](https://hyperide.ai) agent toolchain:

- **[tg-cli](https://git.hyperide.ai/ultrabricks/tg-cli)** — simple Telegram CLI to send messages, photos & files, and a two-way agent bridge (reports, Q→buttons, voice/rich)
- **[review-cli](https://git.hyperide.ai/ultrabricks/review-cli)** — multi-model read-only code review from one command: diff review, cited quorum, brainstorm, visual review, and interactive spec-review tooling. Read-only, CLI-first, harness-agnostic.
- **[agent-tools](https://git.hyperide.ai/ultrabricks/agent-tools)** — the shared catalog `rig` applies: portable agent skills, agent-hooks, the global git-hook dispatcher, CI gates, and MCP servers
- **[draw-cli](https://github.com/alex-mextner/draw-cli)** — text-to-image via Hugging Face
- **[3d-cli](https://github.com/alex-mextner/3d-cli)** — scriptable CLI for the full 3D FDM lifecycle: modeling, mesh repair, slicing, and print monitoring
- **[task-cli](https://git.hyperide.ai/ultrabricks/task-cli)** — enforced ticket-system CLI for agents (GitHub Issues / Linear): acceptance criteria, motivation, and user-impact gates before work starts
- **[dev-cli](https://git.hyperide.ai/ultrabricks/dev-cli)** — project-scoped dev/e2e process runner (start/list/stop dev servers and e2e jobs); rig validates the `scripts:` / `dev:` config shape and provisions `dev:*` / `Bash(dev:*)` as the harness permission surface, without granting raw process/git/package-manager tools
- **[pm-cli](https://git.hyperide.ai/ultrabricks/pm-cli)** — autonomous project-manager coordinator over the task/tg/rig ecosystem: keeps a work queue as a deterministic projection of an append-only event log, reconciling on unforgeable evidence rather than dispatching or editing code itself
- **[rig-cli](https://git.hyperide.ai/ultrabricks/rig-cli)** — sets up a repo (and a dev machine) from a committed `rig.yaml`: skills, agent-hooks, git-hook dispatcher, CI gates, MCP, and the personal CLI ecosystem itself
- **[hyperide.ai](https://hyperide.ai)** — Figma replacement inside VS Code. Edit React components directly through AST/LSP without AI hallucinations, token waste, or context-window limits. Works for indie vibe-coding and for enterprise teams with split design/dev roles.
<!-- /rig:ecosystem-block -->
