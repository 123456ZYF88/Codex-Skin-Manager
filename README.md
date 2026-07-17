# Codex Skin Manager

一个原生 macOS 应用，用主窗口或菜单栏切换已经安装的 Codex Dream Skin 主题、导入完整主题包，并一键恢复 Codex 原版界面。

## 特性

- 原生 SwiftUI 主窗口与 `MenuBarExtra`，无第三方运行依赖。
- 自带原创冰晶武器徽章和完整 Retina 尺寸的原生 macOS 应用图标。
- 从本机 Dream Skin 主题库读取真实预览图；不复制或上传用户素材。
- 切换主题时复用 Dream Skin 的热更新流程，失败时由引擎自动重启 Codex。
- 安全导入 `.codexskin`：限制大小、拒绝目录/链接/路径穿越/多余文件，并原子发布。
- 恢复操作固定调用 `--restore-base-theme --restart-codex`，执行前有破坏性确认。
- 不修改 Codex `app.asar`、应用包或官方代码签名。

## 要求

- macOS 13 或更新版本（当前在 Apple Silicon macOS 上验证）。
- 已安装 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的 macOS 引擎，默认路径：
  `~/.codex/codex-dream-skin-studio`。
- Apple Command Line Tools（用于从源码构建）。

## 构建与安装

```bash
./Scripts/test.sh
./Scripts/build-app.sh
./Scripts/install-app.sh
```

应用安装到 `~/Applications/Codex Skin Manager.app`。安装脚本只向现有 Dream Skin 引擎补充经过测试的主题导入命令，不覆盖其他引擎文件。

## `.codexskin` 格式

主题包是扩展名为 `.codexskin` 的 ZIP，根目录必须恰好包含两个普通文件：

```text
theme.json
background.png   # 也支持 .jpg、.jpeg、.webp
```

`theme.json` 示例见 `Fixtures/sample-theme/theme.json`。导入成功后不会自动应用，需在主题武库中点击“装备主题”。

## 恢复原版

“恢复原版”会恢复 Dream Skin 保存的基础主题并重启 Codex。为了避免中断正在运行的任务，自动化测试只验证参数映射，不会主动执行真实恢复。

## 测试

项目使用零依赖的 Swift 可执行测试 harness，覆盖：

- 主题目录读取、活动主题匹配和符号链接防护；
- 固定命令参数、字面参数传递、超时与 64 KB 输出上限；
- 切换/导入/恢复互斥、最近主题和重复导入确认；
- 主窗口、主题卡与菜单栏视图的编译契约；
- `.codexskin` 恶意归档与原子替换（位于 Dream Skin 引擎测试中）。

## 隐私与版权

公开仓库不包含本机用户名、绝对用户路径、访问令牌、主题库状态、截图、漫画人物图片或用户导入素材。主题预览只在运行时从本机读取。Codex、Dream Skin 和各主题素材的权利归各自权利人所有。

## License

MIT。第三方归属见 `NOTICE` 与 `THIRD_PARTY_LICENSES/`。
