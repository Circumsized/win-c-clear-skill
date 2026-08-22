# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅        |

## Reporting a vulnerability

This skill deletes files on Windows machines, so safety issues are treated as security issues.

**Please do NOT open a public issue for vulnerabilities.** Instead:

- Use GitHub's **private vulnerability reporting** (Security tab → "Report a vulnerability"), or
- Contact the maintainers directly.

Please include:

1. A description of the issue and its potential impact (e.g., data loss, protected-path bypass).
2. Steps or a minimal reproduction (a `-DryRun` reproduction is ideal — never include a real
   destructive reproduction).
3. Affected version / commit.

We aim to acknowledge reports within 7 days and to ship a fix for confirmed issues promptly.

## What counts as a security issue here

- Any bypass of the protected-path blacklist (WinSxS, System32 core, Installer, NTUSER.DAT,
  pagefile/hiberfil, Boot/BCD, etc.).
- Any way to delete without a fresh scan plan or without the required confirmation gates.
- Promotion of unknown/`dangerous` targets to a lower tier without the two-phase protocol.
- Any network exfiltration of files, scan results, or logs.

## Safety-by-design summary

The engine enforces defense-in-depth independent of the agent: plan gate (exit 4), whitelist-only
ids, protected-path blacklist at merge AND delete time, hot-file fence, risky-extension fence,
Restart Manager lock reporting, and audit logging. See
[references/guardrails.md](references/guardrails.md) for the full specification.
