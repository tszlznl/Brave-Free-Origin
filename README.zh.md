# Brave Free Origin (v1.11) — 中文说明

“Brave Free Origin” 是一个 Windows GUI 工具，用来通过企业策略（注册表）把 Brave 精简为类似“Origin” 的本地免费版本，移除 AI、加密钱包、VPN、推广等非必要功能，并提供若干性能/隐私预设。

## 快速开始

1. 将整个文件夹从 ZIP 解压到磁盘（不要在压缩包内运行）。
2. 双击 `Brave-Free-Origin.bat`（启动器）。不要直接双击 `.ps1` 文件——Windows 会用记事本打开它，GUI 不会出现。
3. 在出现的 UAC 提示中点击“是”（需要管理员权限，因为工具会写入 `HKLM` 下的企业策略）。
4. 在 GUI 中点击“Load current state” 查看当前策略状态。
5. 在顶部选择一个模式（Quick Debloat / Recommended / Origin Mode / Privacy + Boost / Max Performance / Max Privacy / Stock），然后点击 `Preview changes` 预览，最后点击 `Apply to Brave` 应用。应用后请完全关闭并重新打开 Brave。
6. （推荐）点击 `Verify` 按钮，工具会读取注册表确认策略是否已生效。

## 按钮与模式说明（摘要）

- Quick Debloat：最轻量的清理，移除最明显的额外功能。安全。 
- Recommended：日常推荐设置，兼顾隐私与可用性。 
- Origin Mode：本地免费实现 Brave 的“Origin”思路。 
- Privacy + Boost：在 Origin 的基础上启用启动/延迟优化，侧重性能。 
- Max Performance：最激进的性能优化与 UI 精简。 
- Max Privacy：严格的隐私锁定（禁用同步、登录、导入等）。
- Stock / None：取消所有勾选，恢复默认（后点 `Apply to Brave`）。

## 重要注意事项

- 工具通过写入 `HKLM\Software\Policies\BraveSoftware\Brave` 来设置企业策略，因此 Brave 会显示 “Managed by your organization” 提示，这属于 Chromium 的透明设计，无法在保留策略的同时隐藏。
- 每次有破坏性操作前都会自动备份（备份目录：`Documents\Brave-Free-Origin-Backups\`）。
- Hosts 编辑使用标记块，可安全移除。
- 若反复出现问题，请使用 `Verify` 报告或还原备份。

## 文件列表（摘要）

- `Brave-Free-Origin.bat` ← 启动器（双击此文件）
- `Brave-Free-Origin.ps1` ← 主脚本（不要直接双击）
- `README.md` ← 英文说明（本文件为中文翻译）
- `LICENSE`
- `images/` ← GUI 截图等资源

---

如果你希望我：
1) 直接把 `Brave-Free-Origin.ps1` 中所有 UI 文本/Description 字段替换为中文，或
2) 在分支中保留英文并创建一个完整的中文脚本副本（例如 `Brave-Free-Origin.zh.ps1`），或
3) 只把 GUI 顶部/帮助/README 等文档翻译保留脚本不动——请告诉我偏好。我已经在分支 `tszlznl-zh-localization` 中工作，准备根据你选择执行下一步。