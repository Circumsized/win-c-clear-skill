# Contributing to win-c-clear-skill

Thanks for your interest! This skill deletes files on real machines, so contributions are held
to a high safety bar. Please read this guide before opening a PR.

## Ground rules (non-negotiable)

1. **Never weaken a safety fence.** The scan-before-delete plan gate, whitelist-only ids,
   protected-path blacklist, hot-file fence, risky-extension fence, and two-phase dangerous
   confirmation are load-bearing. PRs that relax them will be rejected.
2. **Unknown targets default to `dangerous` + `enabled:false`.** Never auto-promote new targets
   to `safe`/`caution` without evidence they are regenerable.
3. **No network upload.** Nothing in the skill may transmit files, scan results, or logs.
4. **Paths via env vars.** All target paths use `%LOCALAPPDATA%`-style variables for portability;
   no hardcoded machine paths.

## Development setup

```powershell
git clone https://github.com/Circumsized/win-c-clear-skill.git
cd win-c-clear-skill
```

Requirements: Windows 10/11 (x64), PowerShell 5.1+ (bundled). Python 3.8+ only if you touch
rule tooling under `tools/`.

## Running the test suite

Run these before every PR; CI runs the same checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_safety.ps1   # guardrails, tiers, contracts
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-engine.ps1   # syntax + C# scanner compile
python tools\test-scan-lists.py                                               # whitelist/blacklist semantics
```

All three must exit 0. If you change engine behavior, add a case to the relevant suite.

## What makes a good contribution

- **New cleanup targets** (`config/targets.json`): include `tier`, `risk` rationale, and verify
  the path is regenerable. Prefer `safe` only for pure caches.
- **Rule data updates** (`assets/rules/`): regenerate via `python tools/fetch_rules.py` and keep
  upstream license attribution intact in the vendored files.
- **Engine fixes** (`scripts/Invoke-CDriveCleanup.ps1`): keep the `JSON_SUMMARY` contract stable
  (`schemaVersion`); add a regression test.
- **Docs** (`references/`): keep them factual and load-on-demand; SKILL.md stays the workflow hub.

## Commit & PR conventions

- Conventional-style messages: `fix:`, `feat:`, `docs:`, `test:`, `refactor:`.
- One logical change per PR; describe the safety impact and how you tested it.
- Keep the `JSON_SUMMARY` schema backward compatible; bump `schemaVersion` only for breaking changes.

## Code of conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

## License of your contribution

By submitting a contribution, you agree it is licensed under the project's
[MIT License](LICENSE). Vendored rule data remains under its upstream licenses.
