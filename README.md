# Brave Free Origin (v1.11 - 中文版)

`Brave Free Origin` 是一个适用于 Windows 的图形界面工具，通过本地企业组策略将普通的 Brave 浏览器改造为极简、低占用的纯净版本，无需为官方的 Brave Origin 付费。

本工具的核心初衷很简单：Brave 官方将“移除 AI、加密货币、VPN、推广营销等冗余内容”的极简构想命名为 Origin 并列为付费升级项目。而本项目通过 Windows 本地策略免费实现相同的效果，并进一步提供针对性能与低延迟的深度优化模式。

本项目灵感源自 [MulesGaming/brave-debullshitinator](https://github.com/MulesGaming/brave-debullshitinator)，并重构为更整洁美观的 WinForms 桌面应用，支持一键预设模式、配置备份、模拟预览、Hosts 域名拦截以及高级脚本管理。

![Brave Free Origin GUI](images/screenshot.png)

---

## 快速上手指南（请先阅读）

**1. 完整解压 ZIP 压缩包中的所有文件。** 请勿直接在压缩包内双击运行——Windows 会限制在临时压缩目录中启动 PowerShell 脚本。

**2. 双击运行 `Brave-Free-Origin.bat`。**

这是推荐的启动器。它会以单次 `-ExecutionPolicy Bypass` 方式启动 PowerShell 并请求管理员权限。

> ⚠️ **重要提示：** 请 **不要** 直接双击 `Brave-Free-Origin.ps1`。Windows 默认会用“记事本”打开 `.ps1` 文件，导致图形界面无法出现。**请始终双击运行 `.bat` 文件。**

**3. 在 UAC（用户账户控制）弹窗中点击“是”。** 本工具需要管理员权限，因为策略将写入注册表 `HKEY_LOCAL_MACHINE\Software\Policies\BraveSoftware\Brave`（企业 IT 部门部署组策略的标准位置）。没有管理员权限则无法应用系统策略。

**4. 进入主界面后，可点击左下方的【读取当前系统状态】（Load current state）**，查看当前电脑上已经生效的策略。

**5. 在顶部彩色按钮栏中选择一种预设模式：**

| 预设按钮 | 功能说明 | 风险级别 |
|---|---|---|
| **快速瘦身 (Quick Debloat)** | 最轻度的精简。仅移除最显眼的商业推广（Rewards 打赏、加密钱包、VPN、Leo AI、密码管理器）。核心体验不受影响。 | 低风险 |
| **推荐配置 (Recommended)** | 均衡的日常主力配置。优秀隐私防护 + 清爽界面 + 保持良好的多媒体兼容性。 | 低风险 |
| **Origin 模式 (Origin Mode)** | 免费对标 Brave 官方付费的“Origin”极简纯净版。默认关闭 AI、钱包、VPN、新闻流、Talk、Tor、时光机等。 | 低风险 |
| **隐私 + 提速 (Privacy + Boost)** | Origin 模式 + 启动加速与网络延迟优化。游戏、影音流媒体推荐的性能基准。 | 中风险 |
| **极致性能 (Max Performance)** | 融合 Origin、隐私提速与强力隐私策略，并进一步精简界面组件。适合极客与游戏玩家的全开优化配置。 | 高风险 |
| **极致隐私 (Max Privacy)** | 强力隐私锁定——禁用同步、账号登录、首次导入、Brave 后台更新服务等。 | 高风险 |
| **恢复默认 (Stock / None)** | 取消所有策略勾选。点击【应用到 Brave】或【完全还原】即可恢复为官方默认状态。 | 无改动 |

**6. （可选）在下方各选项卡中按需微调具体策略：**
- **Brave 功能特性**：GPU 硬件加速开关、Rewards、加密钱包、VPN、Leo AI、Brave News、Brave Talk、Tor、IPFS、WebTorrent 等。
- **隐私与遥测**：P3A 产品分析、使用统计 Ping、Web Discovery、UMA 崩溃上报、Sec-GPC 信号、防指纹追踪、默认广告拦截等。
- **自动填充与密码**：密码管理器、密码泄露检测、地址/信用卡自动填充等。
- **搜索与联想建议**：地址栏联想词、云端拼写检查、Google 翻译弹窗提示等。
- **安全与更新**：安全浏览级别、组件更新等。
- **AI 与生成式 AI**：禁用 Chromium 所有的 GenAI、写作辅助、标签页整理等。
- **网络服务与后台**：关闭窗口后退出后台、预读取连接、DoH 模式、个人资料同步、账号登录等。
- **性能与启动**：QUIC/HTTP3、内存节省模式（休眠闲置标签页）、省电模式、250MB 磁盘缓存上限、空白新标签页启动等。
- **界面冗余与附加功能**：实时字幕、Google Lens 区域搜索/图层搜索、阅读列表、书签栏等。
- **系统组件 (任务/服务)**：管理 Brave Omaha 后台自动更新计划任务与 Windows 服务。
- **Hosts 域名屏蔽 (DNS 级别)**：在 `hosts` 中将 Brave 遥测域名解析定向到 `0.0.0.0`，带专属标记块与自动备份。
- **搜索与启动设置**：独立覆盖默认搜索引擎（如百度、必应、Google、Brave 等）、新标签页地址及启动打开页面。
- **默认脚本规则 (高级)**：查看并手动管理 Brave 组件过滤列表中的 `##+js(...)` 广告拦截脚本规则（仅限手动高级模式）。

**7. 在应用前点击【预览变更】（Preview changes）**：生成模拟运行报告，清晰查看即将新增（ADD）、保持（KEEP）、修改（CHANGE）或清除（CLEAR）的具体项。预览不会对系统做任何写入。

**8. 点击【应用到 Brave】（大绿色按钮）**。随后 **完全关闭并重新启动 Brave 浏览器**（正在运行的标签页需要重启以加载新策略）。

**9. （推荐）点击【校验策略】（Verify）**：程序将回读注册表并比对确认所选策略已全部成功写入。您也可以在 Brave 浏览器中打开 `brave://policy`，检查每条策略是否显示 `Source: Platform`、`Scope: Machine`、`Status: OK`。

---

### 本文件夹中的文件说明

```text
Brave-Free-Origin/
├── Brave-Free-Origin.bat   ← 【双击运行此文件】
├── Brave-Free-Origin.ps1   ← 主程序脚本（请勿直接双击，避免被记事本打开）
├── README.md               ← 本说明文档
├── LICENSE                 ← 开源许可证
└── images/
    ├── screenshot.png      ← 软件界面预览图
    ├── Brave-before.png    ← 优化前内存占用对比
    └── Brave-after.png     ← 优化后内存占用对比
```

启动器（`.bat`）采用单次 `-ExecutionPolicy Bypass` 运行 PowerShell 脚本，仅对本次启动生效，**不会** 降低或永久修改您系统的全局安全策略。

---

## 优化前后效果对比 (Before / After)

以下为优化前后的任务管理器内存占用实测对比：

在测试环境中，优化后 `Brave 浏览器 (7 个进程)` 的常驻内存占用从约 **305.7 MB** 降低到 **222.4 MB**，同时消除了后台遥测、AI 服务与多余连接开销。

### 优化前

![Brave 优化前](images/Brave-before.png)

### 优化后

![Brave 优化后](images/Brave-after.png)

---

## 核心机制与原理

本工具通过向注册表写入 Brave 官方支持的企业组策略（Group Policies）来生效：

`HKLM\Software\Policies\BraveSoftware\Brave`

这意味着它并不是简单地在前端隐藏按钮，而是通过 Chromium 内核底层机制彻底关闭对应模块的功能、后台进程与网络请求。

### 关于“由贵组织管理”(Managed by your organization) 提示

由于本工具写入的是真实的企业级策略（位于 `HKLM\Software\Policies` 下），Brave 浏览器在应用策略后，菜单底部和 `brave://management` 页面中会显示 **“由贵组织管理”** 提示。

这是所有 Chromium 系列浏览器（Chrome、Edge、Brave 等）内置的透明度安全机制，旨在告知用户当前浏览器受系统策略约束。**官方没有提供在保留策略的同时隐藏该提示的途径**。若要移除此提示，只需在工具中取消所有勾选并点击【应用到 Brave】或使用【完全还原】，策略清除后提示即自动消失。此为正常现象而非软件故障。

---

## 还原与回滚说明 (Restore / Undo)

本工具设计了完善的备份与恢复机制：

备份文件统一存放于：
`%USERPROFILE%\Documents\Brave-Free-Origin-Backups\`

1. **完全恢复官方默认状态 (Full Restore)**：
   - 打开本工具，选择目标版本频道，点击右下角红色的 **【完全还原 / 恢复默认】**。
   - 工具将自动删除 Brave 策略注册表项、清除 hosts 屏蔽块、重新启用更新计划任务并将更新服务恢复为手动。
2. **通过注册表备份恢复**：
   - 每次应用前，工具会自动在备份目录下生成 `.reg` 注册表快照，双击对应快照即可还原注册表。
3. **清除 Hosts 屏蔽**：
   - 在【Hosts 域名屏蔽】选项卡中，点击【清除 Hosts 屏蔽块】即可手术式清除本工具添加的解析规则，绝不触碰您的其他自定义 hosts 条目。
4. **脚本规则还原**：
   - 在【默认脚本规则】选项卡中，勾选【高级编辑模式】后可使用【从备份还原选中文件】或【还原所有备份列表】恢复原始规则。

---

## 重要注意事项与常见问题

### 1. 为什么必须使用管理员权限？
本工具需要向注册表 `HKEY_LOCAL_MACHINE` 写入策略，这是 Windows 管理员级别权限。PowerShell 脚本会自动发起提权请求，请在 UAC 弹窗中选择“是”。

### 2. SmartScreen 拦截提示“Windows 已保护你的电脑”怎么办？
如果 Windows 弹出 SmartScreen 提示：
1. 点击 **“更多信息” (More info)**
2. 点击 **“仍要运行” (Run anyway)**

### 3. 下载后提示“此文件来自其他计算机并可能被阻止”
1. 右键点击 `Brave-Free-Origin.bat` 或 `Brave-Free-Origin.ps1`
2. 选择 **“属性” (Properties)**
3. 勾选底部的 **“解除锁定” (Unblock)** 并点击“应用”。

### 4. 杀毒软件 / Windows Defender 会报错吗？
本工具完全开源透明：
- 不修改任何浏览器二进制文件，不注入代码，不劫持 DLL。
- 不添加任何自启动项或隐蔽计划任务。
- 仅调用 Windows 标准注册表管理接口与 hosts 配置文件，并在每次修改前进行自动备份。

### 5. 如何手动在 PowerShell 中运行？
若 BAT 启动异常，可在此文件夹中打开 PowerShell 并执行：
```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Brave-Free-Origin.ps1"
```

---

## 参考与来源 (Sources)

- [Brave 官方帮助中心 - 组策略指南](https://support.brave.com/hc/en-us/articles/360039248271-Group-Policy)
- [Brave 官方帮助中心 - 什么是 Brave Origin？](https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin)
- [brave-core 策略定义源码](https://github.com/brave/brave-core/tree/master/components/policy/resources/templates/policy_definitions/BraveSoftware)
- [Chrome 企业版策略文档](https://chromeenterprise.google/policies/)
- 上游项目：[MulesGaming/brave-debullshitinator](https://github.com/MulesGaming/brave-debullshitinator)
