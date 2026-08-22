## Summary

<!-- One or two sentences: what does this PR change and why? -->

## Safety impact

<!-- REQUIRED: does this touch any safety fence (plan gate, whitelist, blacklist, hot-file,
     risky-extension, two-phase confirmation)? If yes, explain why the change is safe.
     PRs that weaken a fence without strong justification will be rejected. -->

- [ ] This PR does **not** weaken any safety fence
- [ ] This PR touches a safety fence — justification provided below

## Testing

<!-- How did you verify the change? CI runs the three suites below on Windows. -->

- [ ] `tools\verify_safety.ps1` passes
- [ ] `tools\verify-engine.ps1` passes
- [ ] `python tools\test-scan-lists.py` passes
- [ ] Added/updated a regression test for this change (if behavior changed)

## Checklist

- [ ] I have read [CONTRIBUTING.md](CONTRIBUTING.md)
- [ ] `JSON_SUMMARY` contract remains backward compatible (or `schemaVersion` bumped with migration notes)
- [ ] New target paths use env vars (no hardcoded machine paths)
- [ ] Docs updated if behavior/docs changed
