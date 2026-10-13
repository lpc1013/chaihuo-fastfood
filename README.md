# 柴火快餐 · Chaihuo Fast Food

> 毒舌厨神重出江湖 · Godot 重构版（基于网页原型完整重构）

一款像素风快餐经营小游戏。玩家在灶台前接单、备料、烹饪、出餐，穿插剧情章节与图鉴收集。
本仓库为 **Godot 4.7** 引擎的完整重构工程（原网页原型见被忽略的 `legacy_web_v1/`）。

## 技术栈

- 引擎：**Godot 4.7**（渲染后端 `GL Compatibility`，兼容性与性能兼顾）
- 语言：**GDScript**
- 分辨率：1280×720，窗口可缩放（`canvas_items` 拉伸，保持宽高比）
- 运行入口：`res://scenes/main.tscn`

## 运行方式

1. 安装 [Godot 4.7](https://godotengine.org/)（标准版，无需 C#/.NET）。
2. 用 Godot 打开本仓库根目录下的 `project.godot`。
3. 按 **F5** 运行主场景，或直接 **F1** 启动当前场景。

> 说明：导出用的二进制（`builds/windows/*.exe`、`*.pck`）与编辑器缓存（`.godot/`）均被 `.gitignore` 排除，**不纳入版本库**。如需发行版，请在本地用 Godot 的导出功能自行打包。

## 目录结构

| 路径 | 内容 |
|------|------|
| `assets/` | 美术资源：背景、UI、角色、厨房物件等像素图 |
| `data/config/` | 游戏数据（**数据驱动**）：难度 / 经济 / 地图 / 剧情 JSON |
| `scenes/` | Godot 场景文件（`.tscn`） |
| `scripts/` | GDScript 逻辑，含 `autoload` 单例（Config / UiKit / Sfx / Music / GameState / SaveManager） |
| `tests/` | 开发期自动化自检脚本（`autotest.gd`、`chapter_check.gd`） |
| `tools/` | 开发辅助工具（Python / JS）：图集适配、计划生成等 |

## 开发说明

- **数据驱动**：关卡与数值集中在 `data/config/*.json`，改配置即可调参，无需动代码。
- **全局单例**：配置、UI 组件、音效、音乐、游戏状态、存档均通过 `autoload` 在启动时加载。
- **自检**：`tests/` 下的脚本用于回归校验章节数据与自动化流程，建议提交前跑一遍。

## 被版本库忽略的内容

以下目录/文件因体积或属运行时产物，已在 `.gitignore` 中排除，不入库：

- `.godot/`（编辑器导入缓存，约 300MB，可重新生成）
- `legacy_web_v1/`（早期 HTML 原型，仅文档历史引用）
- `builds/windows/*.exe`、`*.pck`（导出二进制）
- `screenshots/`、`deliverables/`、`assets/incoming/`、`saves/`
- `*.log`、`__pycache__/`、`tools/_scratch/`

## License

[MIT License](./LICENSE) © 2026 lpc1013
