# clippingfixer-Angelbody-
Got a body mod and your clothes explode the moment you put shoes on? This rewrites the pack's mesh template so it stops falling back to the vanilla body. One command, backs everything up, fully reversible.

About Release v1.0
## ClippingFixer v1.0

First public release.

**Fixes:** chest/hip clipping through clothing when shoes or feet items are equipped, on rigs using a custom body (ANGEL / EBB / etc.).

**Modes:** `scan` (read-only report) · `apply` · `verify` · `revert`

**Requirements:** Windows, PowerShell 5.1/7, WolvenKit CLI 8.15, .NET 8 runtime.

**Notes:**
- Packs without the target body mesh are reported as `needs-refit` and left untouched.
- Backs up every original and records hashes in `backup/manifest.json` — `revert` always works.
- First full scan is slow (WolvenKit unpacks whole archives); results are cached, second scan is instant.

## License

- MIT
+ [MIT]{LICENSE}

