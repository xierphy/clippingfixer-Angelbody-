# ClippingFixer

**Fixes the "put on shoes → breasts and hips clip through your outfit" bug in Cyberpunk 2077 body mods.**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D4)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE)](#requirements)

---

## The 30-second version

You installed a body mod (HystAngel, EBB, etc.). Most of your clothes look fine…

…until you put on shoes. Then the chest and hips punch straight through the fabric. Take the shoes off, everything is perfect again.

**This tool fixes it in one command.** It rewrites the clothing pack's mesh templates so they always point at the body variant that actually exists in the pack, instead of letting the game guess and pick the wrong one.

```
run.cmd -Mode scan  -Filter "tony_*"          # look, don't touch
run.cmd -Mode apply -Apply -Filter "tony_*"   # fix
```

---

## Why this bug happens

Cyberpunk 2077 clothing packs don't hardcode a mesh path. They use a **runtime template**:

```
*mod\item\item_{gender}_{body}.mesh      # most Tony-style packs
*mod\item\item_{body}.mesh               # Lirael / Subleader style packs
```

That `{body}` is resolved at runtime by `PuppetStateSystem.GetBodyTypeSuffix()`. When a custom body is installed, this lookup frequently falls back to `BaseBody` — so the game loads the **vanilla** body's garment mesh for a **custom** body. The garment is now shaped for a smaller chest/hips, and the body pokes through.

ClippingFixer does the dumb, reliable thing: **it pins the template to the body mesh that's already sitting inside the pack.**

```diff
- *tony_ltph_top\tony_ltph_top_{gender}_{body}.mesh
+ tony_ltph_top\tony_ltph_top_w_angel.mesh
```

No runtime guessing. No game update breakage. No script mods.

---

## Requirements

| What | Notes |
|---|---|
| Windows | PowerShell 5.1 or PowerShell 7 |
| [WolvenKit CLI 8.15](https://github.com/WolvenKit/WolvenKit/releases/tag/8.15.0) | Only `WolvenKit.CLI.exe`; the GUI is not needed |
| .NET 8 Runtime | WolvenKit CLI 8.15 targets .NET 8 |

> WolvenKit 9.x can run the same `unbundle` / `convert` / `pack` commands, but uses a different project/depot setup. This tool is tested on 8.15.

---

## Quick start

**1. Grab the release zip and unzip it somewhere outside your game folder.**

**2. Copy `config.example.json` → `config.json` and edit:**

```json
{
  "gamePath": "E:\\steam\\steamapps\\common\\Cyberpunk 2077",
  "stagePath": "E:\\Vortex Mods\\cyberpunk2077",
  "wolvenkit": "C:\\tools\\WolvenKit.Console-8.15.0\\WolvenKit.CLI.exe",
  "dotnetRoot": "C:\\tools\\dotnet8",
  "bodyTag": "angel",
  "meshCandidates": ["_w_angel", "_angel"]
}
```

- `stagePath` — your Vortex staging folder. Leave empty (`""`) if you don't use Vortex.
- `bodyTag` / `meshCandidates` — your body's suffix. ANGEL → `angel`. If your body mod uses `ebb`, use `ebb` and `["_w_ebb", "_ebb"]`.

**3. Scan first.** Nothing is written in scan mode.

```bat
run.cmd -Mode scan -Filter "tony_*"
```

```
fixable      tony_goth_girl_outfit_3.archive   refs=8 fixable=7 needRefit=1
needs-refit  tony_street_outfit.archive        refs=7 fixable=3 needRefit=4
clean        tony_everyday_outfit.archive      refs=0
```

| State | Meaning |
|---|---|
| `fixable` | The pack contains the target body mesh — this will work |
| `needs-refit` | References exist but the pack has no mesh for that body — patching alone won't help |
| `clean` | No runtime templates at all, nothing to do |

**4. Apply.**

```bat
run.cmd -Mode apply -Apply -Filter "tony_*"
```

Each archive is: backed up → unpacked → `.ent` rewritten → repacked → **entry count verified** → installed to `mods\...\archives\`, plus `archive\pc\mod\` and the Vortex staging folder if a same-named file exists there.

**5. Launch the game and put on shoes.** 😎

---

## Commands

| Flag | Effect |
|---|---|
| `-Mode scan` | Read-only report (default) — writes CSV + log only |
| `-Mode apply` | Requires `-Apply` as a deliberate speed bump |
| `-Mode verify` | Compares live files against `backup\manifest.json` |
| `-Mode revert` | Restores every file from its backup |
| `-Filter "tony_*"` | Only archives matching the wildcard |
| `-Only <file.archive>` | Just one archive |
| `-NoCache` | Ignore `backup\scan-cache.json` and rescan |

### A word about scan speed

WolvenKit's `unbundle` reads the **whole archive** to find matches. A 200 MB clothing pack takes roughly 4 minutes. A first full scan across a large modlist (100+ packs, several GB) can take a couple of hours.

Results are cached in `backup\scan-cache.json`, keyed on path + size + mtime — **the second scan is instant**. Use `-Filter` to keep it sane.

---

## How it works

```
archive -l              list entries (does this pack even have *_w_angel.mesh?)
unbundle                extract
convert serialize       .ent (CR2W) → .json
  (regex-replace the $value holding {gender}_{body} / {body})
convert deserialize     .json → .ent (CR2W)
pack                    repack
entry-count check       guards against stray .json files sneaking in
```

Every modification is recorded in `backup\manifest.json` with the original hash, the new hash, and every path it was installed to. `revert` reads that file — it always goes back.

---

## Known limitations

- **No target mesh in the pack = no fix.** Reported as `needs-refit`. Those are usually shoes, gloves, backpacks, hoods and fur collars. You need to rebuild those meshes with something like [Refit Studio](https://github.com/ANIMEFREG/refit-studio).
- **It does not reshape anything.** It only changes which existing mesh is requested. If a garment was sculpted for a different body, pinning the ANGEL mesh just means "this is now the ANGEL version of that garment".
- **`archive\pc\mod\` copies win.** If an old duplicate of the same pack sits there, it overrides the `mods\` copy. The tool patches every copy it finds — but if you add one later, rerun `scan`.
- **Vortex can undo it.** The tool patches the staging file too, so a normal Deploy usually survives. Reinstalling or updating the mod through Vortex **will** overwrite it — rerun `apply`.
- Only the `{body}` template style is handled. Packs that swap `.app` files by tag at runtime need manual work.

---

## Safety

- Backs up every original before touching it.
- Never modifies an archive it hasn't identified as having runtime templates.
- Verifies entry counts after repacking, so a broken pack is never installed.
- Full rollback via `revert`.
- Exit the game before applying (else files are locked).

---

## 中文说明

**这是什么**：一个修《赛博朋克 2077》"穿上鞋之后胸、臀顶穿衣服"bug 的小工具。

**根因**：很多服装包在 `.ent` 里写的是动态网格模板（`item_{gender}_{body}.mesh`），`{body}` 由游戏运行时解析。装了自定义身体 mod 后，这个值常常回退成 `BaseBody`，衣服就取了原版身体的网格 → 被自定义身体顶穿。上工具把模板直接钉死成包里已有的 `_w_angel.mesh`，不再依赖运行时解析。

**用法**：

```bat
run.cmd -Mode scan  -Filter "tony_*"          # 先看，不改
run.cmd -Mode apply -Apply -Filter "tony_*"   # 改
run.cmd -Mode revert                          # 后悔药
```

**要求**：Windows + PowerShell 5.1/7 + WolvenKit CLI 8.15 + .NET 8。改之前先退游戏。

**注意**：包里没有目标身材网格的条目修不了（报告为 `needs-refit`，多半是鞋、手套、背包），那类得先用 Refit Studio 重做网格。另外 Vortex 重装/更新该 mod 会覆盖暂存文件，需要重跑一次。

---

## Contributing

Issues and PRs welcome. If a pack reports `needs-refit`, attach its `archive -l` output — knowing which mesh suffixes a pack ships is the fastest way to widen `meshCandidates` support.

---

## License

MIT — do whatever you want with it.
