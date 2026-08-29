# generate-zh.ps1
# 读取原始脚本, 用映射表替换 Description 字段为中文, 并输出 Brave-Free-Origin.zh.ps1

$inputPath = "Brave-Free-Origin.ps1"
$outputPath = "Brave-Free-Origin.zh.ps1"

if (-not (Test-Path $inputPath)) {
    Write-Error "未找到 $inputPath"
    exit 1
}

$content = Get-Content -Raw -LiteralPath $inputPath -ErrorAction Stop

$map = @{
    'GPU hardware acceleration. Enabled by default in every mode. Pick Disable (0) to fix GPU driver glitches, artifacts or crashes. Untick the box to leave Brave in control.' = 'GPU 硬件加速。默认启用。选择 Disable (0) 可修复 GPU 驱动问题、图像伪影或崩溃。取消勾选则交由 Brave 控制。'
    'Disable Brave Rewards (BAT ads/tips) and hide all Rewards UI.' = '禁用 Brave Rewards（BAT 广告/小费），并隐藏所有 Rewards 界面。'
    'Disable the built-in crypto wallet (ETH/BTC/SOL/FIL/ZEC).' = '禁用内置加密钱包（ETH/BTC/SOL/FIL/ZEC）。'
    'Disable Brave VPN integration and all VPN UI.' = '禁用 Brave VPN 集成及其所有界面。'
    'Disable Leo AI Chat assistant.' = '禁用 Leo AI 聊天助手。'
    'Disable Brave News feed on the new tab page.' = '在新标签页上禁用 Brave News 资讯。'
    'Disable Brave Talk (Jitsi-based video calls).' = '禁用 Brave Talk（基于 Jitsi 的视频通话）。'
    'Disable the "Check Wayback Machine" prompt on 404 pages.' = '在 404 页面上禁用“检查 Wayback Machine”提示。'
    'Disable Playlist feature (save videos/audio).' = '禁用 Playlist（保存视频/音频）功能。'
    'Disable Speedreader reading-mode feature.' = '禁用 Speedreader 阅读模式功能。'
    'Disable "Private Window with Tor". (Brave Tor is not recommended over real Tor Browser.)' = '禁用“带 Tor 的私人窗口”。（Brave 的 Tor 不如官方 Tor 浏览器建议使用。）'
    'Disable IPFS protocol support.' = '禁用 IPFS 协议支持。'
    'Disable WebTorrent / magnet link integration.' = '禁用 WebTorrent / magnet 链接集成。'
    'Disable P3A privacy-preserving product analytics.' = '禁用 P3A 隐私保护的产品分析。'
    'Disable anonymous daily/weekly/monthly usage ping.' = '禁用匿名的日/周/月 使用统计上报。'
    'Disable Web Discovery Project search index contribution.' = '禁用 Web Discovery Project 的搜索索引贡献。'
    'Disable Chromium UMA crash/usage metrics.' = '禁用 Chromium UMA 崩溃/使用度量。'
    'Enable Sec-GPC "do not sell/share" signal. (Leave ON for privacy.)' = '启用 Sec-GPC “不出售/共享” 信号。（为隐私建议保持开启。）'
    'Reduce language-preference fingerprinting. (Leave ON for privacy.)' = '减少语言偏好指纹攻击。（为隐私建议保持开启。）'
    'Strip tracking params (utm_, fbclid, etc.) from URLs. (Leave ON for privacy.)' = '从 URL 中剥离跟踪参数（utm_, fbclid 等）。（为隐私建议保持开启。）'
    'Bypass Google AMP pages to reach publisher directly. (Leave ON for privacy.)' = '绕过 Google AMP 页面，直接访问发布方。（为隐私建议保持开启。）'
    'Protect against bounce-tracking redirect chains. (Leave ON for privacy.)' = '防护重定向链中的 bounce-tracking。（为隐私建议保持开启。）'
    'Set fingerprint protection to Standard (3). 1=Off.' = '将指纹保护设置为标准（3）。1=关闭。'
    'Force default ad-blocking to Block (2). 1=Allow.' = '强制默认广告拦截为 Block（2）。1=允许。'
    'Force HTTPS upgrade to Strict (2). 3=Standard, 1=Disabled.' = '强制 HTTPS 升级为严格（2）。3=标准，1=禁用。'
    'Cap cross-site referrers to strict-origin-when-cross-origin (2).' = '将跨站引用限制为 strict-origin-when-cross-origin（2）。'
    'Forget first-party storage on tab close (2). 1=Remember.' = '在标签页关闭时忘记第一方存储（2）。1=记住。'
    'Opt out of all Chromium field trials/experiments (2). 1=critical only, 0=all.' = '退出所有 Chromium 实验/字段试验（2）。1=仅关键，0=全部。'
    'Disable enterprise cloud reporting.' = '禁用企业云上报。'
    'Disable the "Send feedback" UI that uploads diagnostics to Brave/Google.' = '禁用会将诊断信息上传到 Brave/Google 的“发送反馈”界面。'
    'Disable built-in password manager (use Bitwarden / Proton Pass instead).' = '禁用内置密码管理器（建议使用 Bitwarden / Proton Pass）。'
    'Disable leaked-credential check (avoids sending hashed pw to Google).' = '禁用泄露密码检测（避免将哈希密码发送到 Google）。'
    'Disable autofill of addresses / contact info.' = '禁用地址/联系人信息的自动填充。'
    'Disable autofill of credit cards.' = '禁用信用卡自动填充。'
    'Prevent sites from querying for saved payment methods.' = '阻止网站查询已保存的支付方式。'
    'Block autoplaying media site-wide.' = '全局阻止媒体自动播放。'
    'Disable search-engine autosuggest in the omnibox.' = '禁用地址栏的搜索引擎自动补全建议。'
    'Disable "Make searches and browsing better" URL reporting.' = '禁用“改进搜索和浏览”的 URL 上报。'
    'Disable the enhanced (cloud) spellcheck service.' = '禁用增强（云端）拼写检查服务。'
    'Disable local spellcheck entirely.' = '完全禁用本地拼写检查。'
    'Disable the "translate this page" Google prompt.' = '禁用 Google 的“翻译此页面”提示。'
    'Disable Google-hosted suggestion page on DNS errors.' = '在 DNS 错误时禁用 Google 托管的建议页面。'
    'Set Safe Browsing to Standard (1). 0=Off, 2=Enhanced (sends more to Google).' = '将安全浏览设为标准（1）。0=关闭，2=增强（会向 Google 发送更多信息）。'
    'Disable sending extra info to Google Safe Browsing.' = '禁用向 Google Safe Browsing 发送额外信息。'
    'Disable uploading downloads to Google for deep scan.' = '禁用将下载内容上传到 Google 进行深度扫描。'
    'Disable Safe Browsing user surveys.' = '禁用安全浏览的用户调查。'
    'Disable Chromium component updates (e.g. Widevine). Only tick if you know what this breaks.' = '禁用 Chromium 组件更新（例如 Widevine）。仅在了解后果时勾选。'
    'Disable the "make default browser" prompt.' = '禁用“设置为默认浏览器”提示。'
    'Disable the software-cleanup scanner (harmless on Brave).' = '禁用软件清理扫描器（在 Brave 上通常无害）。'
    'Disable reporting from the cleanup scanner.' = '禁用来自清理扫描器的上报。'
    'Disable ALL upstream Chromium GenAI features (2).' = '禁用所有上游 Chromium 的 GenAI 功能（2）。'
    'Disable "Help me write" compose features.' = '禁用“帮助我写作”相关的撰写功能。'
    'Disable AI Tab Organizer.' = '禁用 AI 标签页整理器。'
    'Disable AI-generated themes.' = '禁用 AI 生成的主题。'
    'Disable AI-powered history search.' = '禁用 AI 驱动的历史搜索。'
    'Disable GenAI features inside DevTools.' = '在开发者工具中禁用 GenAI 功能。'
    'Stop Brave from running in the background after window close.' = '在窗口关闭后阻止 Brave 在后台运行。'
    'Never prefetch DNS/TCP/SSL (2). 0/1 = predict.' = '从不预取 DNS/TCP/SSL（2）。0/1=预测模式。'
    'Disable legacy cloud-print submissions.' = '禁用旧版云打印提交。'
    'Use OS resolver instead of async DoH client. Only tick if you want OS DNS.' = '使用操作系统的解析器而非异步 DoH 客户端。仅在想使用系统 DNS 时勾选。'
    'Allow DoH ("automatic"). Set to "secure" to force, "off" to disable.' = '允许 DoH（"automatic"）。设为"secure"表示强制，"off" 表示禁用。'
    'Block upload of WebRTC event logs to Google.' = '阻止将 WebRTC 事件日志上传到 Google。'
    'Disable profile sync entirely.' = '完全禁用配置文件同步。'
    'Disable Google/Brave account sign-in.' = '禁用 Google/Brave 帐号登录。'
    'Fully disable sign-in UI (0). 1=allow, 2=force.' = '完全禁用登录界面（0）。1=允许，2=强制。'
    'Disable the welcome/promo new-tab content.' = '禁用欢迎/促销的新标签页内容。'
    'Disable the "welcome back after OS upgrade" tab.' = '禁用“系统升级后欢迎页”标签。'
    'Auto-save to Downloads without prompting. Set 1 if you prefer prompts.' = '不提示直接保存到下载目录。如需提示请设置为 1。'
    'Hide bookmark bar globally (small render win). Unticking lets user toggle.' = '全局隐藏书签栏（小幅渲染优化）。取消勾选则允许用户切换。'
    'Hourly "core" update check launched by Brave Omaha.' = '由 Brave Omaha 启动的每小时“核心”更新检查。'
    'The actual version-check/download task.' = '实际的版本检查/下载任务。'
    'Brave Update Service - main Omaha update service.' = 'Brave 更新服务 - 主 Omaha 更新服务。'
    'Brave Update Service (medium-integrity on-demand helper).' = 'Brave 更新服务（中等权限的按需辅助）。'
    'Brave Elevation Service - helper used by Omaha for per-machine updates.' = 'Brave Elevation Service - Omaha 用于机器级更新的辅助服务。'
    'Brave VPN Service (present only if VPN feature installed).' = 'Brave VPN 服务（仅在安装 VPN 功能时存在）。'
    'Brave VPN Wireguard Service (present only if VPN feature installed).' = 'Brave VPN Wireguard 服务（仅在安装 VPN 功能时存在）。'
    'Privacy-preserving analytics endpoints. Pure telemetry, never user-facing. Safe to block.' = '隐私保护的分析端点。纯遥测，不面向用户。可安全屏蔽。'
    'Field-trial / experiment config. Safe to block - matches ChromeVariations=2 policy.' = '字段试验/实验配置。可安全屏蔽——对应 ChromeVariations=2 策略。'
    'Daily/weekly/monthly anonymous usage ping. Safe to block.' = '日/周/月 的匿名使用统计上报。可安全屏蔽。'
    'Brave Rewards (BAT) servers. Block ONLY if you do not use Rewards. Will break the feature if you turn it on later.' = 'Brave Rewards（BAT）服务器。仅在不使用 Rewards 时屏蔽。若以后开启会导致功能损坏。'
    'News content CDN. Block ONLY if you have disabled News - unblocking is needed if you ever re-enable it.' = '新闻内容 CDN。仅在你已禁用 News 时屏蔽——若将来重新启用需取消屏蔽。'
    'WARNING: blocking this stops Widevine/CRX/iOS-style components from updating. Use only if ComponentUpdatesEnabled is also off.' = '警告：屏蔽此项会阻止 Widevine/CRX/类 iOS 组件更新。仅在同时关闭 ComponentUpdatesEnabled 时使用。'
    'Web Discovery Project endpoints. Already covered by BraveWebDiscoveryEnabled policy; only useful if policy is bypassed.' = 'Web Discovery Project 端点。已由 BraveWebDiscoveryEnabled 策略覆盖；仅在策略被绕过时有用。'
}

$replacer = [System.Text.RegularExpressions.MatchEvaluator]{ param($m)
    $orig = $m.Groups[1].Value
    if ($map.ContainsKey($orig)) {
        return "Description='$($map[$orig])'"
    } else {
        return $m.Value
    }
}

$result = [System.Text.RegularExpressions.Regex]::Replace($content, "Description='([^']*)'", $replacer)

# 保存为 UTF8
Set-Content -LiteralPath $outputPath -Value $result -Encoding UTF8
Write-Output "Wrote $outputPath"
