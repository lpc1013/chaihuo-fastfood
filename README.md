# 柴火快餐 · Chaihuo Fast Food

> 毒舌厨神重出江湖 · Godot 重构版（基于网页原型完整重构）

[![CI](https://github.com/lpc1013/chaihuo-fastfood/actions/workflows/ci.yml/badge.svg)](https://github.com/lpc1013/chaihuo-fastfood/actions/workflows/ci.yml)

一款像素风快餐经营小游戏。玩家在灶台前接单、备料、烹饪、出餐，穿插剧情章节与图鉴收集。
本仓库为 **Godot 4.7** 引擎的完整重构工程（原网页原型见被忽略的 `legacy_web_v1/`）。

## 快速开始

```bash
# 1. 装 Godot 4.7.2（标准版，无需 .NET），或用 scoop/brew 等
#    https://godotengine.org/download/4.7/
# 2. 克隆并打开
git clone https://github.com/lpc1013/chaihuo-fastfood.git
cd chaihuo-fastfood
godot --path . --import        # 首次：生成 .godot/ 导入缓存
godot --path .                 # 直接运行
```

或在编辑器里打开本目录的 `project.godot`，按 **F5** 运行主场景。

> **引擎版本锁定**：本项目以 **Godot 4.7.2**（`4.7.2-stable`）为准。CI 与该版本一一对应，
> 换版本请同步改 `.github/workflows/ci.yml` 顶部的 `GODOT_VERSION`。
> `project.godot` 的 `config/features` 已声明 `4.7`，低版本打开会拒绝。

## 技术栈

- 引擎：**Godot 4.7.2**（渲染后端 `GL Compatibility`，兼容性与性能兼顾）
- 语言：**GDScript**
- 分辨率：1280×720，窗口可缩放（`canvas_items` 拉伸，保持宽高比）
- 运行入口：`res://scenes/main.tscn`

## 自动化自检（CI）

仓库根目录跑 `--test=<模式>` 就能进不同的自检脚本（注册表在 `scripts/screens/main.gd` 的 `_run_test_mode`）：

| 模式 | 跑啥 | 是否需要窗口 |
|------|------|------|
| `smoke` | 主回归套件（331 条：P1/P2 修复点、跨分辨率布局、纯函数闸） | 无头 |
| `border` | 跨章边界 / 存档切换 | 无头 |
| `chapter` | 21 天三章数值曲线与「买得起吗」实判 | 无头 |
| `trace` | 单局全量打点，产出行 md5 可对拍 | 无头 |
| `artcheck` | 全量美术资源引用检查 | 可用无头 |
| `soak` | 长时间跑机（帧率 / 内存泄漏） | 需窗口 |
| `perf` | 逐帧耗时 / 布局计算开销 / 内存曲线 | 需窗口 |
| `balance` | 参数化经济曲线（不同 APS 下的出餐/流失） | 无头 |

**本地一键闸门**（与 CI 同源，提交前跑）：

```bash
tools/ci.sh            # 纯逻辑套件（快）
tools/ci.sh --full     # 追加取帧/计时套件（Linux/WSL 需 xvfb-run）
tools/ci.sh --export   # 额外验证导出 preset 可用
```

CI（`.github/workflows/ci.yml`）在每次 push / PR 上跑：脚本语法闸 → 排除目录 `.gd` 抢注检查 →
无头套件 → 取帧套件（xvfb）→ 导出可用性。

> **为什么要单独做"引擎报错"闸**：Godot 的 `SCRIPT ERROR` / `Parse Error` **不计入**任何 `check()`，
> 于是可能出现"GDScript 一路报错、测试却 `failed=0 ALL PASS`"。所以 `tools/ci.sh` 与 CI
> 既看 `checks=` 也 grep 日志里的引擎报错，任一命中即判 FAIL。

## 目录结构

| 路径 | 内容 |
|------|------|
| `assets/` | 美术资源：背景、UI、角色、厨房物件等像素图 |
| `data/config/` | 游戏数据（**数据驱动**）：难度 / 经济 / 地图 / 剧情 JSON |
| `scenes/` | Godot 场景文件（`.tscn`） |
| `scripts/` | GDScript 逻辑，含 `autoload` 单例（Config / UiKit / Sfx / Music / GameState / SaveManager）与纯函数核心模块（`core/`：DaySim / PlayLayout / UnlockRules / Economics / CookingSystem） |
| `tests/` | 开发期自动化自检脚本（`smoke_test.gd`、`chapter_check.gd` 等，见上表） |
| `tools/` | 开发辅助工具：Python/JS 图集处理、`verify.sh` / `ci.sh` 本地闸门 |

> 说明：导出二进制（`builds/windows/*.exe`、`*.pck`）与编辑器缓存（`.godot/`）均被 `.gitignore` 排除，**不纳入版本库**。发行版请在本地用 Godot 的导出功能自行打包（预设名 `Windows Desktop`）。

## 开发说明

- **数据驱动**：关卡与数值集中在 `data/config/*.json`，改配置即可调参，无需动代码。
  启动时会跑 `Config.validate_config()`（id 唯一、食材引用、烹饪时间 >0、效果键白名单、章节完整性），
  配置写坏会在启动日志里直接报错，不会静默带病运行。
- **纯函数核心**：可测逻辑（烹饪速度、布局几何、解锁规则、经济收支）抽到 `scripts/core/` 下的
  `class_name` 静态方法，不依赖场景树，便于离线单测——这也是 `smoke` 套件里那些"纯函数闸"的来源。
- **全局单例**：配置、UI 组件、音效、音乐、游戏状态、存档均通过 `autoload` 在启动时加载。
- **存档一致性**：每次 `save_all()` 会同时给玩家存档与营业台账打同一个 `commit_id`；
  读档时若两者不一致（暗示台账没存上）会告警并以玩家存档为准。写盘走"临时文件 + `.bak` + rename"，
  中途断电不会留下半截 JSON。
- **提交前**：先跑 `tools/ci.sh`（或 `tools/ci.sh --full`），与 CI 同一套闸。

## 被版本库忽略的内容

以下目录/文件因体积或属运行时产物，已在 `.gitignore` 中排除，不入库：

- `.godot/`（编辑器导入缓存，约 300MB，可重新生成）
- `legacy_web_v1/`（早期 HTML 原型，仅文档历史引用）
- `builds/windows/*.exe`、`*.pck`（导出二进制）
- `screenshots/`、`deliverables/`、`assets/incoming/`、`saves/`
- `*.log`、`__pycache__/`、`tools/_scratch/`

## License

[MIT License](./LICENSE) © 2026 lpc1013
