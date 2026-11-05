# clippingfixer

把《赛博朋克 2077》服装包里"身材模板"钉死成指定身材（默认 ANGEL），修掉**穿上鞋 / 脚模之后胸、臀被顶穿**的问题。

> 适用前提：你装了 HystAngel（或其它改名到 `angel` 的身体 mod），并且衣服包内部**自带该身材的网格**（`*_w_angel.mesh` / `*_angel.mesh`）。

---

## 它到底在修什么

很多服装包在实体（`.ent`）里写的是**动态网格路径模板**：

```
*mod\item\item_{gender}_{body}.mesh        # Tony 系（Leather and Lace / Goth Girl / Everyday …）
*mod\item\item_{body}.mesh                 # Lirael / Subleader 系
```

`{body}` 在运行时由 `PuppetStateSystem.GetBodyTypeSuffix()` 解析。装了身体 mod 之后，这个值经常解析成 `BaseBody`（原版身材），于是衣服去取原版身材的网格 → 胸、臀被 ANGEL 身体顶出来。

clippingfixer 做的事很简单：**把模板直接替换成包里已经存在的 ANGEL 网格文件名**，不再依赖运行时解析。

```diff
- *tony_ltph_top\tony_ltph_top_{gender}_{body}.mesh
+ tony_ltph_top\tony_ltph_top_w_angel.mesh
```

如果包内**没有** ANGEL 网格，本工具不会乱改（报告成 `needs-review`），你只能用 Refit Studio 之类工具重做网格。

---

## 依赖

| 需要 | 说明 |
|---|---|
| Windows + PowerShell 5.1 或 PowerShell 7 | `run.cmd` 会自动挑一个 |
| [WolvenKit CLI 8.15](https://github.com/WolvenKit/WolvenKit/releases/tag/8.15.0) | 只要 `WolvenKit.CLI.exe`，不需要图形界面 |
| .NET 8 运行时 | WolvenKit CLI 8.15 的目标框架 |

> WolvenKit 9.x 也能跑 `unbundle` / `convert` / `pack`，但它需要额外的 depot 设置，本项目按 8.15 验证过。

---

## 快速开始

1. 解压到一个目录（不要放在游戏目录里）。
2. 复制 `config.example.json` 为 `config.json`，改这四项：

```json
{
  "gamePath": "E:\\steam\\steamapps\\common\\Cyberpunk 2077",
  "stagePath": "E:\\Vortex Mods\\cyberpunk2077",
  "wolvenkit": "C:\\tools\\WolvenKit.Console-8.15.0\\WolvenKit.CLI.exe",
  "dotnetRoot": "C:\\tools\\dotnet8",
  "bodyTag": "angel",
  "meshCandidates": ["w_angel", "angel"]
}
```

- `stagePath` 是 Vortex 的暂存目录，**没有就留空**（只用 mods / archive\pc\mod）。
- `bodyTag` 与 `meshCandidates` 换成你的身体 mod 的后缀（例如 `hyst`、`ebb`）。

3. **先扫一遍，别急着改**：

```bat
run.cmd -Mode scan -Filter "tony_*"
```

输出示例：

```
fixable      tony_goth_girl_outfit_3.archive  refs=8 fixable=7 needRefit=1
needs-review  tony_street_outfit.archive       refs=7 fixable=3 needRefit=4
clean        tony_everyday_outfit.archive     refs=0
```

- `fixable`：包内有 ANGEL 网格，能直接改。
- `needs-review`：有引用，但包内缺目标身材的网格。**这不等于一定会穿模**：实测鞋、手套、背包、宽松外套这类条目本来就有 10 mm 以上的间隙，游戏回退到 `base_body` 网格也看不出来；真正会顶穿的是紧身衣物（连衣裙 / 上衣 / 内衣）。要确认只能量网格，或者进游戏试穿。
- `clean`：没有模板引用，无需处理。

4. 确认没问题后执行：

```bat
run.cmd -Mode apply -Apply -Filter "tony_*"
```

改完会自动：备份原包 → 校验条目数 → 安装到 `mods\...\archives\`、`archive\pc\mod\`（若存在同名文件）、Vortex 暂存区（若存在同名文件）。

5. 想撤销：

```bat
run.cmd -Mode revert
```

6. 想确认当前状态是否还是改过的版本：

```bat
run.cmd -Mode verify
```

---

## 参数

| 参数 | 作用 |
|---|---|
| `-Mode scan\|apply\|revert\|verify` | 默认 `scan` |
| `-Apply` | `apply` 模式必须显式带上，防误操作 |
| `-Filter <通配符>` | 只处理文件名匹配的 archive，例如 `"tony_*"` |
| `-Only <文件名>` | 只处理一个 archive |
| `-NoCache` | 忽略 `backup\scan-cache.json`，强制重新扫描 |
| `-Config <路径>` | 指定配置文件 |
| `-BackupDir` / `-ReportDir` / `-WorkDir` | 自定义备份 / 报告 / 临时目录 |

### 为什么建议先用 -Filter

WolvenKit 的 `unbundle` 是**按整包扫描**的，一个 200 MB 的包要 ~4 分钟。首次全量扫描所有存档（150 个包、数 GB）可能要一两个小时。

已经扫过的包会写进 `backup\scan-cache.json`（按路径 + 大小 + 修改时间做键），**第二次扫描是秒级**。

---

## 目录结构

```
clippingfixer/
├─ clippingfixer.ps1        # 主脚本
├─ run.cmd                  # 启动器（自动选 pwsh / powershell）
├─ config.example.json      # 配置模板
├─ config.json              # 你本机的配置（不随包分发）
├─ backup/
│  ├─ manifest.json         # 每个改过的包的原始/新哈希、安装路径（revert 靠它）
│  ├─ scan-cache.json       # 扫描缓存
│  └─ <原包>.archive        # 原包备份（第一次 apply 时生成）
└─ reports/
   ├─ clippingfixer-*.log   # 运行日志
   └─ scan-*.csv            # 扫描报告
```

**`backup\` 不要删** —— 回滚要用它。

---

## 安全须知

1. **改之前请退出游戏**，否则文件被占用会写失败。
2. **不要在 Vortex 里点 Deploy 之后再改**：Vortex 会用暂存区重建硬链接，把改动冲掉。本工具会同时改暂存区的同名文件，所以大多数情况下 Deploy 不会回退——但**Vortex 重新安装 / 更新该 mod 会覆盖暂存文件**。
3. 每条修改都记录在 `backup\manifest.json`（原始哈希 + 新哈希 + 所有安装路径），所以 `revert` 一定回得去。
4. 脚本只碰**名字匹配**且**里面确实有模板引用**的 archive，不会动其它文件。
5. 第一次 `apply` 会先把原包完整复制进 `backup\`，留出双倍空间。

---

## 已知限制

- **包内没有目标身材网格**时无法修复（报告为 `needs-review`）。这类条目通常是鞋、手套、背包、帽子、毛领等，需要先用 [Refit Studio](https://github.com/ANIMEFREG/refit-studio) 之类工具重建网格。
- **只改模板，不重建网格**：如果衣服本身的网格是按别的身材做的，钉死 ANGEL 网格只会让它"变成 ANGEL 版的衣服"，不会自动贴合。
- `archive\pc\mod\` 里可能存在同名旧副本，加载顺序会盖过 `mods\` 那份。本工具会一并改掉（前提是它存在于该目录）。
- 工具只处理 `{body}` 模板这一种写法；如果某个包用的是别的动态机制（例如运行时按 tag 切换 `.app`），需要单独处理。

---

## 原理速查

```
archive -l            列出条目（用于确认包里有没有 *_w_angel.mesh）
unbundle              解包
convert serialize     .ent → .json
  （正则替换 $value 里的 {gender}_{body} / {body}）
convert deserialize   .json → .ent（CR2W）
pack                  重新打包
条目数比对             防止 serialize 残留 json 被打进包
```

---

## License

MIT
