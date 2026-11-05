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

- MIT License

Copyright (c) 2026 clippingfixer contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
