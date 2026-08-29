﻿# ============================================================================
#  Brave Free Origin (Brave Debullshitinator Pro) - Windows 图形界面中文版
#  通过注册表应用 Brave 浏览器企业组策略，提供清晰的复选框配置界面。
#  策略源自 brave/brave-core 及 Chromium 企业文档深度调研。
# ============================================================================

#region Elevation -------------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args
    exit
}
#endregion

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:BravePolicyPath = 'HKLM:\Software\Policies\BraveSoftware\Brave'

# ---- Multi-channel support (v1.5) -------------------------------------------
# Each Brave channel keeps its own policy hive. Default target is Stable.
# If user picks "All installed channels", every detected install gets the apply.
$script:Channels = [ordered]@{
    'Stable'  = @{
        Path = 'HKLM:\Software\Policies\BraveSoftware\Brave'
        InstallProbes = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
        )
    }
    'Beta'    = @{
        Path = 'HKLM:\Software\Policies\BraveSoftware\Brave-Beta'
        InstallProbes = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser-Beta\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser-Beta\Application\brave.exe",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Beta\Application\brave.exe"
        )
    }
    'Nightly' = @{
        Path = 'HKLM:\Software\Policies\BraveSoftware\Brave-Nightly'
        InstallProbes = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser-Nightly\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser-Nightly\Application\brave.exe",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Nightly\Application\brave.exe"
        )
    }
    'Dev'     = @{
        Path = 'HKLM:\Software\Policies\BraveSoftware\Brave-Dev'
        InstallProbes = @(
            "$env:ProgramFiles\BraveSoftware\Brave-Browser-Dev\Application\brave.exe",
            "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser-Dev\Application\brave.exe",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Dev\Application\brave.exe"
        )
    }
}
$script:TargetChannels = @('Stable')
$script:ScriptletUserDataRoots = [ordered]@{
    'Stable'  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    'Beta'    = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Beta\User Data"
    'Nightly' = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Nightly\User Data"
    'Dev'     = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser-Dev\User Data"
}
$script:ScriptletDisablePrefix = '! BFO disabled: '
$script:ScriptletRules = @()
$script:ScriptletVisibleRules = @()
$script:ScriptletScanState = $null
$script:ScriptletScanTimer = $null
$script:ScriptletRenderState = $null
$script:ScriptletRenderTimer = $null
$script:ScriptletFilterTimer = $null
$script:ScriptletCheckedKeys = @{}
$script:SuppressScriptletStatusEvents = $false
$script:ScriptletComponentNames = @{
    'iodkpdagapdfkphljnddpjlldadblomo' = 'uBlock 过滤规则 (uBlock filters)'
    'adcocjohghhfpidemphmcmlmhnfgikei' = 'Brave 第一方特定规则 (Brave Firstparty filters)'
    'cdbbhgbmjhfnhnmgeddbliobbofkgdhe' = 'EasyList Cookie 规则'
    'kihnoaefogbkmblfimmibknnmkllbhlf' = 'EasyPrivacy 隐私规则'
    'flnkmpokemfpaajmiimmjeiandgoodgg' = 'AdGuard 法语规则 (AdGuard French)'
}

function Get-DetectedChannels {
    $found = @()
    foreach ($name in $script:Channels.Keys) {
        foreach ($probe in $script:Channels[$name].InstallProbes) {
            if (Test-Path $probe) { $found += $name; break }
        }
    }
    return $found
}

#region Policy Data -----------------------------------------------------------
# Each policy: Name, Type (DWORD/STRING), ApplyValue (what to write when ticked),
#              Recommended (true = tick by default in "Recommended" preset),
#              MaxPrivacy (tick for "Maximum Privacy"), Description
$script:Policies = [ordered]@{
    'Brave 功能特性' = @(
        @{Name='HardwareAccelerationModeEnabled'; Type='DWORD'; ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Choices=([ordered]@{'开启 (1)'=1; '关闭 (0)'=0}); Description='GPU 硬件加速。所有预设模式下默认开启。如果遇到 GPU 驱动异常、画面伪影或崩溃，可选择【关闭 (0)】。取消勾选则交由 Brave 自行管理。'},
        @{Name='BraveRewardsDisabled';         Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Brave Rewards（BAT 广告/打赏）并隐藏所有 Rewards 界面元素。'},
        @{Name='BraveWalletDisabled';          Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用内置加密钱包（ETH/BTC/SOL/FIL/ZEC 等）。'},
        @{Name='BraveVPNDisabled';             Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Brave VPN 集成及所有 VPN 界面元素。'},
        @{Name='BraveAIChatEnabled';           Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Leo AI 助手聊天功能。'},
        @{Name='BraveNewsDisabled';            Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用新标签页上的 Brave News 新闻资讯流。'},
        @{Name='BraveTalkDisabled';            Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Brave Talk（基于 Jitsi 的视频通话）。'},
        @{Name='BraveWaybackMachineEnabled';   Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='禁用 404 页面上的【检查 Wayback Machine 网页时光机存档】提示。'},
        @{Name='BravePlaylistEnabled';         Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='禁用播放列表（Playlist）功能（保存音视频）。'},
        @{Name='BraveSpeedreaderEnabled';      Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='禁用 Speedreader 速读/阅读模式功能。'},
        @{Name='TorDisabled';                  Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$false; Description='禁用【使用 Tor 的私密窗口】。（建议需要时使用真正的 Tor 浏览器，而非 Brave 内置 Tor。）'},
        @{Name='IPFSEnabled';                  Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 IPFS 分布式协议支持。'},
        @{Name='WebTorrentDisabled';           Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 WebTorrent / 磁力链接集成。'}
    )
    '隐私与遥测' = @(
        @{Name='BraveP3AEnabled';                             Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 P3A 隐私保护产品分析。'},
        @{Name='BraveStatsPingEnabled';                       Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用每日/每周/每月的匿名使用情况 Ping 统计上报。'},
        @{Name='BraveWebDiscoveryEnabled';                    Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Web Discovery Project 搜索索引贡献计划。'},
        @{Name='MetricsReportingEnabled';                     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Chromium UMA 崩溃与使用情况统计上报。'},
        @{Name='BraveGlobalPrivacyControlEnabled';            Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='启用 Sec-GPC【禁止出售/共享个人数据】信号。（为保护隐私建议保持开启。）'},
        @{Name='BraveReduceLanguageEnabled';                  Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='减少语言偏好指纹追踪。（为保护隐私建议保持开启。）'},
        @{Name='BraveTrackingQueryParametersFilteringEnabled';Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='从 URL 中自动剥离追踪参数（如 utm_、fbclid 等）。（为保护隐私建议保持开启。）'},
        @{Name='BraveDeAmpEnabled';                           Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='绕过 Google AMP 页面，直接访问原始发布站点。（为保护隐私建议保持开启。）'},
        @{Name='BraveDebouncingEnabled';                      Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='防护反弹追踪（Bounce Tracking）重定向链。（为保护隐私建议保持开启。）'},
        @{Name='DefaultBraveFingerprintingV2Setting';         Type='DWORD';  ApplyValue=3; Recommended=$true;  MaxPrivacy=$true;  Description='将指纹防护设置为标准级别（3）。1 为关闭。'},
        @{Name='DefaultBraveAdblockSetting';                  Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='将默认广告拦截设置为拦截（2）。1 为允许。'},
        @{Name='DefaultBraveHttpsUpgradeSetting';             Type='DWORD';  ApplyValue=2; Recommended=$false; MaxPrivacy=$true;  Description='强制将 HTTPS 升级设置为严格模式（2）。3 为标准，1 为禁用。'},
        @{Name='DefaultBraveReferrersSetting';                Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='将跨站 Referrer 限制为 strict-origin-when-cross-origin（2）。'},
        @{Name='DefaultBraveRemember1PStorageSetting';        Type='DWORD';  ApplyValue=2; Recommended=$false; MaxPrivacy=$true;  Description='关闭标签页时清除第一方存储（2）。1 为保留。'},
        @{Name='ChromeVariations';                            Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='退出所有 Chromium 线上试验/功能测试（2）。1 为仅限关键，0 为全部。'},
        @{Name='CloudReportingEnabled';                       Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用企业云端报告。'},
        @{Name='UserFeedbackAllowed';                         Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用向 Brave/Google 上传诊断信息的【发送反馈】功能。'}
    )
    '自动填充与密码' = @(
        @{Name='PasswordManagerEnabled';        Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用内置密码管理器（建议改用 Bitwarden / 1Password / Proton Pass 等专业工具）。'},
        @{Name='PasswordLeakDetectionEnabled';  Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用泄露凭据检测（避免将哈希密码发送至 Google 校验）。'},
        @{Name='AutofillAddressEnabled';        Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用地址与联系人信息的自动填充。'},
        @{Name='AutofillCreditCardEnabled';     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用信用卡信息的自动填充。'},
        @{Name='PaymentMethodQueryEnabled';     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='阻止网站查询您已保存的支付方式。'},
        @{Name='AutoplayAllowed';               Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='在全站范围内阻止媒体自动播放。'}
    )
    '搜索与联想建议' = @(
        @{Name='SearchSuggestEnabled';                        Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用地址栏（Omnibox）中的搜索引擎自动联想建议。'},
        @{Name='UrlKeyedAnonymizedDataCollectionEnabled';     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用【改善搜索和浏览体验】的 URL 数据上报。'},
        @{Name='SpellCheckServiceEnabled';                    Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用增强型（云端）拼写检查服务。'},
        @{Name='SpellcheckEnabled';                           Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='彻底禁用本地拼写检查。'},
        @{Name='TranslateEnabled';                            Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Google 的【翻译此页面】弹窗提示。'},
        @{Name='AlternateErrorPagesEnabled';                  Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 DNS 解析错误时 Google 托管的建议页面。'}
    )
    '安全与更新' = @(
        @{Name='SafeBrowsingProtectionLevel';         Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$false; Description='将安全浏览（Safe Browsing）设置为标准模式（1）。0 为关闭，2 为增强模式（会上报更多数据至 Google）。'},
        @{Name='SafeBrowsingExtendedReportingEnabled';Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用向 Google 安全浏览发送额外信息。'},
        @{Name='SafeBrowsingDeepScanningEnabled';     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用将下载文件上传至 Google 进行深度安全扫描。'},
        @{Name='SafeBrowsingSurveysEnabled';          Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用安全浏览用户满意度调查。'},
        @{Name='ComponentUpdatesEnabled';             Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='禁用 Chromium 组件更新（如 Widevine DRM）。仅在明确了解影响时勾选。'},
        @{Name='DefaultBrowserSettingEnabled';        Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用【设为默认浏览器】的弹窗提示。'},
        @{Name='ChromeCleanupEnabled';                Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用软件清理扫描器（Software Cleanup Scanner）。'},
        @{Name='ChromeCleanupReportingEnabled';       Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用清理扫描器的结果上报。'}
    )
    'AI 与生成式 AI' = @(
        @{Name='GenAiDefaultSettings';      Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用所有上游 Chromium 生成式 AI（GenAI）功能（2）。'},
        @{Name='HelpMeWriteSettings';       Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用【帮我写作】（Help me write）撰写辅助功能。'},
        @{Name='TabOrganizerSettings';      Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 AI 标签页整理器（Tab Organizer）。'},
        @{Name='CreateThemesSettings';      Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 AI 主题生成功能。'},
        @{Name='HistorySearchSettings';     Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 AI 历史记录搜索功能。'},
        @{Name='DevToolsGenAiSettings';     Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁用开发者工具（DevTools）内部的 GenAI 功能。'}
    )
    '网络服务与后台' = @(
        @{Name='BackgroundModeEnabled';           Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='关闭窗口后阻止 Brave 继续在后台运行进程。'},
        @{Name='NetworkPredictionOptions';        Type='DWORD';  ApplyValue=2; Recommended=$true;  MaxPrivacy=$true;  Description='禁止预读取 DNS/TCP/SSL 连接（2）。0/1 为预测预取。'},
        @{Name='CloudPrintSubmitEnabled';         Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用已废弃的云打印（Cloud Print）提交功能。'},
        @{Name='BuiltInDnsClientEnabled';         Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='使用系统原生 DNS 解析器而非异步 DoH 客户端。仅在需要系统 DNS 时勾选。'},
        @{Name='DnsOverHttpsMode';                Type='STRING'; ApplyValue='automatic'; Recommended=$true;  MaxPrivacy=$true;  Description='允许 DoH（"automatic" 自动模式）。设为 "secure" 为强制使用，"off" 为禁用。'},
        @{Name='WebRtcEventLogCollectionAllowed'; Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='阻止将 WebRTC 事件日志上传至 Google。'},
        @{Name='SyncDisabled';                    Type='DWORD';  ApplyValue=1; Recommended=$false; MaxPrivacy=$true;  Description='彻底禁用个人资料同步（Sync）功能。'},
        @{Name='SigninAllowed';                   Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='禁用 Google/Brave 账户登录。'},
        @{Name='BrowserSignin';                   Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='彻底禁用浏览器登录界面（0）。1 为允许，2 为强制。'},
        @{Name='PromotionalTabsEnabled';          Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用新标签页上的欢迎与推广营销内容。'},
        @{Name='WelcomePageOnOSUpgradeEnabled';   Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用系统升级后弹出的【欢迎回来】页面。'},
        @{Name='ImportAutofillFormData';          Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='首次运行时阻止导入自动填充表单数据。'},
        @{Name='ImportBookmarks';                 Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='首次运行时阻止书签导入提示。'},
        @{Name='ImportHistory';                   Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='首次运行时阻止历史记录导入。'},
        @{Name='ImportSavedPasswords';            Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='首次运行时阻止已保存密码导入。'},
        @{Name='ImportSearchEngine';              Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$true;  Description='首次运行时阻止搜索引擎导入。'}
    )
    '性能与启动' = @(
        @{Name='QuicAllowed';                     Type='DWORD';  ApplyValue=1;          Recommended=$true;  MaxPrivacy=$true;  Description='启用 QUIC / HTTP/3 协议。加快 TLS 握手速度，降低延迟。'},
        @{Name='HighEfficiencyModeEnabled';       Type='DWORD';  ApplyValue=1;          Recommended=$true;  MaxPrivacy=$true;  Description='内存节省模式：休眠闲置标签页以释放 RAM 内存和 CPU 资源。'},
        @{Name='BatterySaverModeAvailability';    Type='DWORD';  ApplyValue=2;          Recommended=$true;  MaxPrivacy=$true;  Description='低电量时允许开启省电模式（2）。1 为未插电时常开，0 为禁用。'},
        @{Name='MediaRouterEnabled';              Type='DWORD';  ApplyValue=0;          Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Google Cast / Media Router。停止后台 mDNS 局域网发现并减少内存占用。'},
        @{Name='DiskCacheSize';                   Type='DWORD';  ApplyValue=262144000;  Recommended=$true;  MaxPrivacy=$false; Description='将磁盘缓存上限限制为 250 MB（数值单位为字节）。防止 SSD 硬盘缓存无节制膨胀。'},
        @{Name='BrowserLabsEnabled';              Type='DWORD';  ApplyValue=0;          Recommended=$true;  MaxPrivacy=$true;  Description='隐藏工具栏中的 Labs / 实验性功能图标。'},
        @{Name='RestoreOnStartup';                Type='DWORD';  ApplyValue=5;          Recommended=$true;  MaxPrivacy=$true;  Description='启动时打开空白新标签页（5）。比恢复上次会话（1）更快。'},
        @{Name='HomepageIsNewTabPage';            Type='DWORD';  ApplyValue=0;          Recommended=$true;  MaxPrivacy=$true;  Description='将主页按钮与庞大的新标签页（NTP）解绑。'},
        @{Name='HomepageLocation';                Type='STRING'; ApplyValue='about:blank'; Recommended=$true;  MaxPrivacy=$true;  Description='空白主页（about:blank）= 最快的启动速度。'},
        @{Name='NewTabPageLocation';              Type='STRING'; ApplyValue='about:blank'; Recommended=$false; MaxPrivacy=$true;  Description='强制将新标签页设为 about:blank。消除所有新标签页多余负担。'},
        @{Name='NTPCustomBackgroundEnabled';      Type='DWORD';  ApplyValue=0;          Recommended=$true;  MaxPrivacy=$true;  Description='禁用新标签页自定义背景壁纸（停止壁纸下载网络开销）。'},
        @{Name='ShowHomeButton';                  Type='DWORD';  ApplyValue=0;          Recommended=$false; MaxPrivacy=$false; Description='隐藏主页按钮（微小的界面渲染收益）。'}
    )
    '界面冗余与附加功能' = @(
        @{Name='LiveCaptionEnabled';              Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用实时字幕（停止语音识别模型的后台自动下载）。'},
        @{Name='AccessibilityImageLabelsEnabled'; Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用云端图片描述服务（避免将图片上传至 Google 分析）。'},
        @{Name='LensDesktopNTPSearchEnabled';     Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='隐藏新标签页上的 Google Lens 智慧镜头搜索框。'},
        @{Name='LensRegionSearchEnabled';         Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='禁用右键菜单中的 Google Lens 区域搜索。'},
        @{Name='LensOverlaySettings';             Type='DWORD';  ApplyValue=1; Recommended=$true;  MaxPrivacy=$true;  Description='禁用 Google Lens 屏幕图层搜索功能（1 为禁用）。'},
        @{Name='ReadingListEnabled';              Type='DWORD';  ApplyValue=0; Recommended=$true;  MaxPrivacy=$true;  Description='移除【阅读列表】界面。'},
        @{Name='PromptForDownloadLocation';       Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='自动保存下载文件至【下载】目录且不再每次询问。如需每次询问请设为 1。'},
        @{Name='BookmarkBarEnabled';              Type='DWORD';  ApplyValue=0; Recommended=$false; MaxPrivacy=$false; Description='全局隐藏书签栏（微小的渲染性能收益）。取消勾选则允许用户自由切换。'}
    )
}

$script:ScheduledTasks = @(
    @{Name='BraveSoftwareUpdateTaskMachineCore'; Description='Brave Omaha 启动的每小时【核心】更新检查任务。'},
    @{Name='BraveSoftwareUpdateTaskMachineUA';   Description='实际执行版本检查与安装包下载的更新任务。'}
)

$script:Services = @(
    @{Name='brave';                   Description='Brave Update Service - 主要的 Omaha 更新服务。'},
    @{Name='bravem';                  Description='Brave Update Service (medium-integrity) - 中等完整性按需辅助更新服务。'},
    @{Name='BraveElevationService';   Description='Brave Elevation Service - Omaha 用于按设备更新的提权服务。'},
    @{Name='BraveVPNService';         Description='Brave VPN Service（仅在安装了 VPN 功能时存在）。'},
    @{Name='BraveVpnWireguardService';Description='Brave VPN Wireguard Service（仅在安装了 VPN 功能时存在）。'}
)

# ---- Hosts 域名屏蔽分组 (v1.5) -----------------------------------------------
# 通过 Windows hosts 文件实现 DNS 级别拦截。
$script:HostsBlocks = @(
    @{Name='Brave P3A 遥测';           Recommended=$true;  Domains=@('p3a.brave.com','p3a-creative.brave.com','p2a.brave.com','p2a-creative.brave.com');                Description='隐私保护分析接口。纯后台遥测，非面向用户服务。可安全屏蔽。'},
    @{Name='Brave 实验配置 (Variations)'; Recommended=$true;  Domains=@('variations.brave.com','go-updater.brave.com');                                                    Description='线上测试/功能实验配置。可安全屏蔽 - 对应 ChromeVariations=2 策略。'},
    @{Name='Brave 使用统计 Ping';        Recommended=$true;  Domains=@('laptop-updates.brave.com');                                                                       Description='每日/每周/每月匿名使用情况 Ping 统计。可安全屏蔽。'},
    @{Name='Brave Rewards / BAT 打赏'; Recommended=$false; Domains=@('rewards.brave.com','grant.rewards.brave.com','creators.brave.com');                               Description='Brave Rewards (BAT) 服务器。仅在您不使用 Rewards 时屏蔽。若日后开启该功能需先解除屏蔽。'},
    @{Name='Brave News 新闻 CDN';        Recommended=$false; Domains=@('brave-today-cdn.brave.com','brave-today.brave.com');                                              Description='新闻内容 CDN。仅在您已禁用新闻资讯流时屏蔽 - 若重新开启新闻需先解除屏蔽。'},
    @{Name='组件更新 (Component Updates)';Recommended=$false; Domains=@('componentupdater.brave.com','brave-core-ext.s3.brave.com');                                       Description='【警告】屏蔽此项将阻止 Widevine DRM/CRX 等组件更新。仅在 ComponentUpdatesEnabled 同样关闭时使用。'},
    @{Name='网络探索 (Web Discovery)';    Recommended=$false; Domains=@('search.anonymous.brave.com','wdp.brave.com');                                                     Description='Web Discovery Project 接口。已由 BraveWebDiscoveryEnabled 策略覆盖；仅在策略被绕过时起效。'}
)
$script:HostsSentinelStart = '# === Brave-Free-Origin START - managed block, do not edit between sentinels ==='
$script:HostsSentinelEnd   = '# === Brave-Free-Origin END ==='
$script:HostsFile = "$env:WINDIR\System32\drivers\etc\hosts"

# ---- 搜索引擎配置 (v1.6) ----------------------------------------------------
$script:SearchEngines = [ordered]@{
    'Brave 搜索 (Brave Search)' = @{ URL='https://search.brave.com/search?q={searchTerms}';     Suggest='https://search.brave.com/api/suggest?q={searchTerms}';                       Keyword='brave';     Home='https://search.brave.com' }
    '百度 (Baidu)'              = @{ URL='https://www.baidu.com/s?wd={searchTerms}';             Suggest='https://suggestion.baidu.com/su?wd={searchTerms}&action=opensearch';        Keyword='baidu';     Home='https://www.baidu.com' }
    '必应 (Bing)'               = @{ URL='https://www.bing.com/search?q={searchTerms}';          Suggest='https://www.bing.com/osjson.aspx?query={searchTerms}';                      Keyword='bing';      Home='https://www.bing.com' }
    'Google'                    = @{ URL='https://www.google.com/search?q={searchTerms}';        Suggest='https://www.google.com/complete/search?output=chrome&q={searchTerms}';     Keyword='google';    Home='https://www.google.com' }
    'DuckDuckGo'                = @{ URL='https://duckduckgo.com/?q={searchTerms}';             Suggest='https://duckduckgo.com/ac/?q={searchTerms}&type=list';                      Keyword='ddg';       Home='https://duckduckgo.com' }
    'Startpage'                 = @{ URL='https://www.startpage.com/do/search?q={searchTerms}';  Suggest='';                                                                          Keyword='startpage'; Home='https://www.startpage.com' }
    'Qwant'                     = @{ URL='https://www.qwant.com/?q={searchTerms}';               Suggest='https://api.qwant.com/api/suggest?q={searchTerms}';                         Keyword='qwant';     Home='https://www.qwant.com' }
    'Ecosia'                    = @{ URL='https://www.ecosia.org/search?q={searchTerms}';        Suggest='https://ac.ecosia.org/?q={searchTerms}';                                    Keyword='ecosia';    Home='https://www.ecosia.org' }
    'Mojeek'                    = @{ URL='https://www.mojeek.com/search?q={searchTerms}';        Suggest='';                                                                          Keyword='mojeek';    Home='https://www.mojeek.com' }
    'Kagi (付费搜索)'            = @{ URL='https://kagi.com/search?q={searchTerms}';              Suggest='https://kagi.com/api/autosuggest?q={searchTerms}';                          Keyword='kagi';      Home='https://kagi.com' }
    'Yandex'                    = @{ URL='https://yandex.com/search/?text={searchTerms}';        Suggest='https://suggest.yandex.com/suggest-ff.cgi?part={searchTerms}';             Keyword='yandex';    Home='https://yandex.com' }
    '自定义 (Custom)...'        = @{ URL='';                                                     Suggest='';                                                                          Keyword='custom';    Home='';                                IsCustom=$true }
}

# 新标签页与启动特定网页预设
$script:DestinationOptions = [ordered]@{
    '空白页 (about:blank)'                      = 'about:blank'
    '默认新标签页 (不覆盖)'                    = '__SKIP__'
    '与上方选定的搜索引擎主页一致'              = '__SEARCH__'
    'Brave Search 首页'                         = 'https://search.brave.com'
    '百度首页 (Baidu)'                          = 'https://www.baidu.com'
    '必应首页 (Bing)'                           = 'https://www.bing.com'
    'Google 首页'                               = 'https://www.google.com'
    'DuckDuckGo 首页'                           = 'https://duckduckgo.com'
    '自定义网址 (Custom URL)...'                = '__CUSTOM__'
}

# 启动行为模式 (RestoreOnStartup 策略值)
$script:StartupModes = [ordered]@{
    '打开新标签页'                  = @{ Code=5; UsesURL=$false }
    '恢复上次打开的会话'            = @{ Code=1; UsesURL=$false }
    '打开空白页 (about:blank)'      = @{ Code=4; UsesURL=$true; FixedURL='about:blank' }
    '打开特定网页或一组网页'        = @{ Code=4; UsesURL=$true; FixedURL=$null }
}
#endregion

#region Helpers ---------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    if ($script:LogBox) {
        $script:LogBox.AppendText("$line`r`n")
        $script:LogBox.SelectionStart = $script:LogBox.Text.Length
        $script:LogBox.ScrollToCaret()
    }
}

function Get-ExistingPolicy {
    param([string]$Name)
    try {
        $v = Get-ItemProperty -Path $script:BravePolicyPath -Name $Name -ErrorAction Stop
        return $v.$Name
    } catch { return $null }
}

function Set-PolicyValue {
    param([string]$Name, [string]$Type, $Value)
    if (-not (Test-Path $script:BravePolicyPath)) {
        New-Item -Path $script:BravePolicyPath -Force | Out-Null
    }
    $regType = if ($Type -eq 'DWORD') { 'DWord' } else { 'String' }
    New-ItemProperty -Path $script:BravePolicyPath -Name $Name -Value $Value -PropertyType $regType -Force | Out-Null
}

function Remove-PolicyValue {
    param([string]$Name)
    try {
        Remove-ItemProperty -Path $script:BravePolicyPath -Name $Name -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Export-Backup {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $env:USERPROFILE 'Documents\Brave-Free-Origin-Backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $file = Join-Path $dir "brave-policies-backup-$stamp.reg"
    $regKey = 'HKLM\Software\Policies\BraveSoftware'
    $result = & reg.exe EXPORT $regKey $file /y 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Backup saved: $file" 'OK'
        return $file
    } else {
        Write-Log "Backup skipped (no existing policies)." 'INFO'
        return $null
    }
}

function Test-BraveInstalled {
    $paths = @(
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:ProgramFiles(x86)\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    return $null
}

# ---- Hosts file helpers (v1.5) ----------------------------------------------
function Backup-HostsFile {
    if (-not (Test-Path $script:HostsFile)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $env:USERPROFILE 'Documents\Brave-Free-Origin-Backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $file = Join-Path $dir "hosts-backup-$stamp.bak"
    Copy-Item $script:HostsFile $file -Force
    Write-Log "Hosts backup saved: $file" 'OK'
    return $file
}

function Get-HostsCurrentDomains {
    if (-not (Test-Path $script:HostsFile)) { return @() }
    $lines = Get-Content $script:HostsFile -ErrorAction SilentlyContinue
    $inBlock = $false
    $domains = @()
    foreach ($line in $lines) {
        if ($line -eq $script:HostsSentinelStart) { $inBlock = $true; continue }
        if ($line -eq $script:HostsSentinelEnd)   { $inBlock = $false; continue }
        if ($inBlock -and $line -match '^\s*0\.0\.0\.0\s+(\S+)') {
            $domains += $Matches[1]
        }
    }
    return $domains
}

function Set-HostsBlockDomains {
    param([string[]]$Domains)
    [void](Backup-HostsFile)

    # Read all lines, strip out our existing sentinel block (if any)
    $lines = if (Test-Path $script:HostsFile) { Get-Content $script:HostsFile } else { @() }
    $kept = New-Object System.Collections.ArrayList
    $skipping = $false
    foreach ($line in $lines) {
        if ($line -eq $script:HostsSentinelStart) { $skipping = $true; continue }
        if ($line -eq $script:HostsSentinelEnd)   { $skipping = $false; continue }
        if (-not $skipping) { [void]$kept.Add($line) }
    }

    # Trim trailing blank lines from existing content for tidiness
    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
        $kept.RemoveAt($kept.Count - 1)
    }

    if ($Domains -and $Domains.Count -gt 0) {
        [void]$kept.Add('')
        [void]$kept.Add($script:HostsSentinelStart)
        [void]$kept.Add("# Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') by Brave Free Origin. Remove via the GUI.")
        foreach ($d in ($Domains | Sort-Object -Unique)) {
            [void]$kept.Add("0.0.0.0 $d")
        }
        [void]$kept.Add($script:HostsSentinelEnd)
    }

    # ASCII encoding - matches what Windows expects for hosts. Some AVs flag UTF-16 hosts.
    Set-Content -Path $script:HostsFile -Value $kept -Encoding ASCII -Force

    # Flush DNS so the change takes effect immediately for new connections
    & ipconfig.exe /flushdns | Out-Null
    Write-Log "Hosts block written: $($Domains.Count) domain(s). DNS cache flushed." 'OK'
}

function Clear-HostsBlock {
    Set-HostsBlockDomains -Domains @()
    Write-Log 'Hosts sentinel block removed.' 'OK'
}
# -----------------------------------------------------------------------------

function Get-BraveVersion {
    $exe = Test-BraveInstalled
    if ($exe) {
        try { return (Get-Item $exe).VersionInfo.FileVersion } catch { return 'unknown' }
    }
    return 'not installed'
}

function Show-TextReport {
    param(
        [string]$Title,
        [string]$Text,
        [string]$DefaultFileName = 'brave-free-origin-report.txt'
    )

    $rf = New-Object System.Windows.Forms.Form
    $rf.Text = $Title
    $rf.Size = New-Object System.Drawing.Size(760, 560)
    $rf.StartPosition = 'CenterParent'
    $rf.MinimumSize = New-Object System.Drawing.Size(620, 420)

    $buttons = New-Object System.Windows.Forms.Panel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 44
    $rf.Controls.Add($buttons)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = 'Both'
    $tb.WordWrap = $false
    $tb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $tb.Dock = 'Fill'
    $tb.Text = $Text
    $rf.Controls.Add($tb)

    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = '复制 (Copy)'
    $copy.Size = New-Object System.Drawing.Size(100, 28)
    $copy.Location = New-Object System.Drawing.Point(10, 8)
    $copy.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($tb.Text)
    })
    $buttons.Controls.Add($copy)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = '保存报告 (Save)'
    $save.Size = New-Object System.Drawing.Size(115, 28)
    $save.Location = New-Object System.Drawing.Point(118, 8)
    $save.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = '文本报告 (*.txt)|*.txt'
        $sfd.FileName = $DefaultFileName
        $sfd.InitialDirectory = Join-Path $env:USERPROFILE 'Documents\Brave-Free-Origin-Backups'
        if (-not (Test-Path $sfd.InitialDirectory)) { New-Item -ItemType Directory -Path $sfd.InitialDirectory | Out-Null }
        if ($sfd.ShowDialog() -eq 'OK') {
            Set-Content -Path $sfd.FileName -Value $tb.Text -Encoding UTF8
            Write-Log "报告已保存: $($sfd.FileName)" 'OK'
        }
    })
    $buttons.Controls.Add($save)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = '关闭 (Close)'
    $close.Size = New-Object System.Drawing.Size(100, 28)
    $close.Location = New-Object System.Drawing.Point(240, 8)
    $close.Add_Click({ $rf.Close() })
    $buttons.Controls.Add($close)

    $buttons.BringToFront()
    [void]$rf.ShowDialog()
}

function Get-RegistryValueState {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }
    try {
        $props = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [pscustomobject]@{ Exists = $true; Value = $props.PSObject.Properties[$Name].Value }
    } catch {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }
}

function Get-RegistryNumberedValues {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $props = Get-ItemProperty -Path $Path
    $items = @()
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -match '^\d+$') {
            $items += [pscustomobject]@{ Index = [int]$p.Name; Value = $p.Value }
        }
    }
    return @($items | Sort-Object Index | ForEach-Object { $_.Value })
}

function Get-SelectedHostsDomains {
    $domains = @()
    if ($script:HostsCheckBoxes) {
        foreach ($cb in $script:HostsCheckBoxes) {
            if ($cb.Checked) { $domains += $cb.Tag.Domains }
        }
    }
    return @($domains | Sort-Object -Unique)
}

function Get-DesiredSearchOverride {
    $desired = [ordered]@{}
    if (-not $script:ChkSearchOverride.Checked) { return $desired }

    $engineKey = $script:CmbSearchEngine.SelectedItem
    $eng = $script:SearchEngines[$engineKey]
    $url = $eng.URL
    $sug = $eng.Suggest
    $name = $engineKey
    $keyword = $eng.Keyword

    if ($eng.IsCustom) {
        $url = $script:TxtCustomSearchUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($url)) { throw 'Custom search URL is empty.' }
        if ($url -notmatch '\{searchTerms\}') { throw 'Custom search URL must contain {searchTerms}.' }
        $name = 'Custom Search'
    }

    $desired['DefaultSearchProviderEnabled'] = @{ Type='DWORD'; Value=1 }
    $desired['DefaultSearchProviderName'] = @{ Type='STRING'; Value=$name }
    $desired['DefaultSearchProviderKeyword'] = @{ Type='STRING'; Value=$keyword }
    $desired['DefaultSearchProviderSearchURL'] = @{ Type='STRING'; Value=$url }
    if ($sug) { $desired['DefaultSearchProviderSuggestURL'] = @{ Type='STRING'; Value=$sug } }
    return $desired
}

function Get-DesiredNtpOverride {
    $desired = [ordered]@{}
    if (-not $script:ChkNtpOverride.Checked) { return $desired }

    $engineKey = $script:CmbSearchEngine.SelectedItem
    $engineHome = if ($script:SearchEngines[$engineKey].IsCustom) { '' } else { $script:SearchEngines[$engineKey].Home }
    $url = Resolve-Destination -DropdownLabel $script:CmbNtpDest.SelectedItem -CustomUrl $script:TxtNtpCustomUrl.Text -SearchEngineHome $engineHome
    if ([string]::IsNullOrWhiteSpace($url)) { throw 'New tab override has no resolvable URL.' }
    $desired['NewTabPageLocation'] = @{ Type='STRING'; Value=$url }
    return $desired
}

function Get-DesiredStartupOverride {
    if (-not $script:ChkStartupOverride.Checked) {
        return [pscustomobject]@{ Enabled = $false; Code = $null; Urls = @() }
    }

    $modeKey = $script:CmbStartupMode.SelectedItem
    $mode = $script:StartupModes[$modeKey]
    $urls = @()
    if ($mode.UsesURL) {
        $urls = if ($mode.FixedURL) { @($mode.FixedURL) }
                else { @($script:TxtStartupUrl.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        if ($urls.Count -eq 0) { throw 'Startup override has no URL.' }
    }
    return [pscustomobject]@{ Enabled = $true; Code = $mode.Code; Urls = $urls }
}

function Add-RegistryPlanLines {
    param(
        [System.Text.StringBuilder]$Report,
        [string]$Path,
        [System.Collections.IDictionary]$Desired,
        [string[]]$Names,
        [string]$Title
    )

    [void]$Report.AppendLine("  -- $Title")
    $changes = 0
    foreach ($name in $Names) {
        $state = Get-RegistryValueState -Path $Path -Name $name
        if ($Desired.Contains($name)) {
            $target = $Desired[$name].Value
            if (-not $state.Exists) {
                [void]$Report.AppendLine("     ADD    $name = $target")
                $changes++
            } elseif ("$($state.Value)" -eq "$target") {
                [void]$Report.AppendLine("     KEEP   $name = $target")
            } else {
                [void]$Report.AppendLine("     CHANGE $name : $($state.Value) -> $target")
                $changes++
            }
        } elseif ($state.Exists) {
            [void]$Report.AppendLine("     CLEAR  $name (currently $($state.Value))")
            $changes++
        }
    }
    if ($changes -eq 0) { [void]$Report.AppendLine('     No write needed.') }
}

function New-HostsPlanReport {
    $desired = @(Get-SelectedHostsDomains)
    $current = @(Get-HostsCurrentDomains)
    $toAdd = @($desired | Where-Object { $current -notcontains $_ })
    $toKeep = @($desired | Where-Object { $current -contains $_ })
    $toRemove = @($current | Where-Object { $desired -notcontains $_ })

    $report = New-Object System.Text.StringBuilder
    [void]$report.AppendLine('Brave Free Origin Hosts 域名屏蔽预览')
    [void]$report.AppendLine("生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$report.AppendLine("目标文件: $($script:HostsFile)")
    [void]$report.AppendLine('')
    [void]$report.AppendLine("已选中分组数: $(@($script:HostsCheckBoxes | Where-Object { $_.Checked }).Count)")
    [void]$report.AppendLine("当前托管域名数: $($current.Count)")
    [void]$report.AppendLine("目标托管域名数: $($desired.Count)")
    [void]$report.AppendLine('')
    [void]$report.AppendLine("新增屏蔽 (Add): $($toAdd.Count)")
    foreach ($d in $toAdd) { [void]$report.AppendLine("  + $d") }
    [void]$report.AppendLine("保持现状 (Keep): $($toKeep.Count)")
    foreach ($d in $toKeep) { [void]$report.AppendLine("  = $d") }
    [void]$report.AppendLine("从托管块移除 (Remove): $($toRemove.Count)")
    foreach ($d in $toRemove) { [void]$report.AppendLine("  - $d") }
    [void]$report.AppendLine('')
    [void]$report.AppendLine('说明：不会修改系统 hosts 中的其他任何自定义条目。本工具仅维护 Brave-Free-Origin 专属标记块。')
    return $report.ToString()
}

function New-ApplyPlanReport {
    $report = New-Object System.Text.StringBuilder
    $modeKey = if ([string]::IsNullOrWhiteSpace($script:ActiveProfile)) { 'Custom' } else { $script:ActiveProfile }
    $modeLabel = if ($script:ProfileDisplayNames.ContainsKey($modeKey)) { $script:ProfileDisplayNames[$modeKey] } else { $modeKey }

    [void]$report.AppendLine('Brave Free Origin 策略应用预览报告')
    [void]$report.AppendLine("生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$report.AppendLine("预设模式: $modeLabel")
    [void]$report.AppendLine("目标版本频道: $($script:TargetChannels -join ', ')")
    [void]$report.AppendLine("应用前备份: $($chkBackup.Checked)")
    [void]$report.AppendLine('')
    [void]$report.AppendLine('【注意】这是一次模拟运行（Dry Run）。尚未对系统注册表进行任何实际写入。')
    [void]$report.AppendLine('')

    foreach ($channel in $script:TargetChannels) {
        $path = $script:Channels[$channel].Path
        [void]$report.AppendLine("=== $channel  ($path) ===")
        $adds = 0; $changes = 0; $clears = 0; $keeps = 0

        foreach ($cb in $script:CheckBoxes) {
            $p = $cb.Tag.Policy
            $state = Get-RegistryValueState -Path $path -Name $p.Name
            if ($cb.Checked) {
                if (-not $state.Exists) {
                    [void]$report.AppendLine("  ADD    $($p.Name) = $($p.ApplyValue)")
                    $adds++
                } elseif ("$($state.Value)" -eq "$($p.ApplyValue)") {
                    [void]$report.AppendLine("  KEEP   $($p.Name) = $($p.ApplyValue)")
                    $keeps++
                } else {
                    [void]$report.AppendLine("  CHANGE $($p.Name) : $($state.Value) -> $($p.ApplyValue)")
                    $changes++
                }
            } elseif ($state.Exists) {
                [void]$report.AppendLine("  CLEAR  $($p.Name) (currently $($state.Value))")
                $clears++
            }
        }
        [void]$report.AppendLine("  统计: $adds 个新增, $changes 个修改, $clears 个清除, $keeps 个已正确")
        [void]$report.AppendLine('')

        try {
            $searchDesired = Get-DesiredSearchOverride
            Add-RegistryPlanLines -Report $report -Path $path -Desired $searchDesired -Names @(
                'DefaultSearchProviderEnabled',
                'DefaultSearchProviderName',
                'DefaultSearchProviderKeyword',
                'DefaultSearchProviderSearchURL',
                'DefaultSearchProviderSuggestURL'
            ) -Title 'Search override'
        } catch {
            [void]$report.AppendLine("  -- Search override")
            [void]$report.AppendLine("     ERROR: $_")
        }
        [void]$report.AppendLine('')

        try {
            $ntpDesired = Get-DesiredNtpOverride
            Add-RegistryPlanLines -Report $report -Path $path -Desired $ntpDesired -Names @('NewTabPageLocation') -Title 'New tab override'
        } catch {
            [void]$report.AppendLine("  -- New tab override")
            [void]$report.AppendLine("     ERROR: $_")
        }
        [void]$report.AppendLine('')

        try {
            $startup = Get-DesiredStartupOverride
            [void]$report.AppendLine('  -- Startup override')
            $curStartup = Get-RegistryValueState -Path $path -Name 'RestoreOnStartup'
            $urlPath = Join-Path $path 'RestoreOnStartupURLs'
            $curUrls = @(Get-RegistryNumberedValues -Path $urlPath)
            if ($startup.Enabled) {
                if (-not $curStartup.Exists) {
                    [void]$report.AppendLine("     ADD    RestoreOnStartup = $($startup.Code)")
                } elseif ("$($curStartup.Value)" -eq "$($startup.Code)") {
                    [void]$report.AppendLine("     KEEP   RestoreOnStartup = $($startup.Code)")
                } else {
                    [void]$report.AppendLine("     CHANGE RestoreOnStartup : $($curStartup.Value) -> $($startup.Code)")
                }
                if ($startup.Urls.Count -gt 0) {
                    [void]$report.AppendLine("     REPLACE RestoreOnStartupURLs with $($startup.Urls.Count) URL(s): $($startup.Urls -join ', ')")
                } elseif ($curUrls.Count -gt 0) {
                    [void]$report.AppendLine('     CLEAR  RestoreOnStartupURLs')
                } else {
                    [void]$report.AppendLine('     No startup URL list needed.')
                }
            } else {
                if ($curStartup.Exists) { [void]$report.AppendLine("     CLEAR  RestoreOnStartup (currently $($curStartup.Value))") }
                if ($curUrls.Count -gt 0) { [void]$report.AppendLine("     CLEAR  RestoreOnStartupURLs ($($curUrls.Count) URL(s))") }
                if (-not $curStartup.Exists -and $curUrls.Count -eq 0) { [void]$report.AppendLine('     No write needed.') }
            }
        } catch {
            [void]$report.AppendLine('  -- Startup override')
            [void]$report.AppendLine("     ERROR: $_")
        }
        [void]$report.AppendLine('')
    }

    [void]$report.AppendLine('=== 计划任务 (Scheduled Tasks) ===')
    foreach ($cb in $script:TaskCheckBoxes) {
        $t = $cb.Tag
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        if (-not $task) {
            [void]$report.AppendLine("  MISSING $($t.Name) - skipped")
        } elseif ($cb.Checked) {
            if ($task.State -eq 'Disabled') { [void]$report.AppendLine("  KEEP    $($t.Name) disabled") }
            else { [void]$report.AppendLine("  DISABLE $($t.Name) (currently $($task.State))") }
        } else {
            if ($task.State -eq 'Disabled') { [void]$report.AppendLine("  ENABLE  $($t.Name)") }
            else { [void]$report.AppendLine("  KEEP    $($t.Name) enabled/current state $($task.State)") }
        }
    }
    [void]$report.AppendLine('')

    [void]$report.AppendLine('=== Windows 系统服务 (Services) ===')
    foreach ($cb in $script:ServiceCheckBoxes) {
        $s = $cb.Tag
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if (-not $svc) {
            [void]$report.AppendLine("  MISSING $($s.Name) - skipped")
        } elseif ($cb.Checked) {
            if ($svc.StartType -eq 'Disabled') { [void]$report.AppendLine("  KEEP    $($s.Name) disabled") }
            else { [void]$report.AppendLine("  DISABLE $($s.Name) (currently $($svc.StartType), $($svc.Status))") }
        } else {
            if ($svc.StartType -eq 'Disabled') { [void]$report.AppendLine("  RESET   $($s.Name) startup type to Manual") }
            else { [void]$report.AppendLine("  KEEP    $($s.Name) startup type $($svc.StartType)") }
        }
    }
    [void]$report.AppendLine('')

    [void]$report.AppendLine('=== Hosts 域名屏蔽列表 ===')
    [void]$report.AppendLine('说明：【应用到 Brave】主按钮不会修改 hosts。如需生效请在 Hosts 选项卡内点击【应用 Hosts 屏蔽】。')
    [void]$report.AppendLine("当前勾选的 Hosts 屏蔽域名总数: $(@(Get-SelectedHostsDomains).Count)")

    return $report.ToString()
}

function Invoke-FullRestore {
    param([bool]$Backup)

    if ($Backup) { [void](Export-Backup) }

    foreach ($channel in $script:TargetChannels) {
        $path = $script:Channels[$channel].Path
        try {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Removed policy key for $channel ($path)" 'OK'
            } else {
                Write-Log "$channel had no policy key - skipped." 'INFO'
            }
        } catch {
            Write-Log "Full restore policy remove [$channel]: $_" 'ERR'
        }
    }

    $currentHosts = @(Get-HostsCurrentDomains)
    if ($currentHosts.Count -gt 0) {
        try { Clear-HostsBlock } catch { Write-Log "Full restore hosts clear: $_" 'ERR' }
    } else {
        Write-Log 'No Brave-Free-Origin hosts block present.' 'INFO'
    }

    foreach ($t in $script:ScheduledTasks) {
        try {
            $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($task -and $task.State -eq 'Disabled') {
                Enable-ScheduledTask -TaskName $t.Name -ErrorAction Stop | Out-Null
                Write-Log "ENABLED task $($t.Name)" 'OK'
            }
        } catch {
            Write-Log "Full restore task $($t.Name): $_" 'WARN'
        }
    }

    foreach ($s in $script:Services) {
        try {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -eq 'Disabled') {
                Set-Service -Name $s.Name -StartupType Manual -ErrorAction Stop
                Write-Log "RESET service $($s.Name) to Manual" 'OK'
            }
        } catch {
            Write-Log "Full restore service $($s.Name): $_" 'WARN'
        }
    }

    $script:SuppressSelectionEvents = $true
    foreach ($cb in $script:CheckBoxes)        { $cb.Checked = $false }
    foreach ($cb in $script:TaskCheckBoxes)    { $cb.Checked = $false }
    foreach ($cb in $script:ServiceCheckBoxes) { $cb.Checked = $false }
    foreach ($cb in $script:HostsCheckBoxes)   { $cb.Checked = $false }
    if ($script:ChkSearchOverride)  { $script:ChkSearchOverride.Checked = $false }
    if ($script:ChkNtpOverride)     { $script:ChkNtpOverride.Checked = $false }
    if ($script:ChkStartupOverride) { $script:ChkStartupOverride.Checked = $false }
    $script:SuppressSelectionEvents = $false
    $script:ActiveProfile = 'None'
    Update-SelectionSummary
    Write-Log 'Full restore completed. Restart Brave to see stock behavior.' 'DONE'
}

function Get-ScriptletDefaultRoot {
    $channel = if ($script:TargetChannels -and $script:TargetChannels.Count -gt 0) { $script:TargetChannels[0] } else { 'Stable' }
    if ($script:ScriptletUserDataRoots.Contains($channel)) { return $script:ScriptletUserDataRoots[$channel] }
    return $script:ScriptletUserDataRoots['Stable']
}

function Get-ScriptletComponentInfo {
    param([string]$File, [string]$Root)

    $componentId = 'unknown'
    $version = 'unknown'
    $source = 'Unknown filter list'
    try {
        $full = [System.IO.Path]::GetFullPath($File)
        $base = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $full.Substring($base.Length)
            $parts = $relative -split '[\\/]'
            if ($parts.Count -ge 1) { $componentId = $parts[0] }
            if ($parts.Count -ge 2) { $version = $parts[1] }
        }
        if ($script:ScriptletComponentNames.ContainsKey($componentId)) {
            $source = $script:ScriptletComponentNames[$componentId]
        } elseif ($componentId -ne 'unknown') {
            $source = $componentId
        }
    } catch {}

    return [pscustomobject]@{
        ComponentId = $componentId
        Version     = $version
        Source      = $source
    }
}

function Get-BfoDisabledScriptletRule {
    param([string]$Line)
    if ($Line -match '^\s*!\s*BFO disabled:\s*(?<rule>.+)$') {
        return $Matches.rule.Trim()
    }
    return $null
}

function Get-ScriptletRuleFromLine {
    param([string]$Line)
    $disabled = Get-BfoDisabledScriptletRule -Line $Line
    if ($disabled) { return $disabled }

    $trimmed = $Line.Trim()
    if ($trimmed.StartsWith('!')) { return $null }
    return $trimmed
}

function ConvertTo-ScriptletRecord {
    param(
        [string]$File,
        [string]$Root,
        [string]$Line,
        [int]$LineNumber
    )

    $disabledRule = Get-BfoDisabledScriptletRule -Line $Line
    $enabled = -not [bool]$disabledRule
    $rule = if ($disabledRule) { $disabledRule } else { $Line.Trim() }
    if ([string]::IsNullOrWhiteSpace($rule)) { return $null }
    if ($rule.StartsWith('!')) { return $null }
    if ($rule -notmatch '##\+js\((?<body>.*)\)') { return $null }

    $marker = $rule.IndexOf('##+js(', [System.StringComparison]::Ordinal)
    if ($marker -lt 0) { return $null }
    $domain = $rule.Substring(0, $marker)
    $body = $Matches.body
    $scriptlet = $body
    $arguments = ''
    $comma = $body.IndexOf(',')
    if ($comma -ge 0) {
        $scriptlet = $body.Substring(0, $comma).Trim()
        $arguments = $body.Substring($comma + 1).Trim()
    } else {
        $scriptlet = $body.Trim()
    }

    $info = Get-ScriptletComponentInfo -File $File -Root $Root
    return [pscustomobject]@{
        Enabled     = $enabled
        Domain      = $domain
        Scriptlet   = $scriptlet
        Arguments   = $arguments
        Source      = $info.Source
        ComponentId = $info.ComponentId
        Version     = $info.Version
        File        = $File
        LineNumber  = $LineNumber
        Rule        = $rule
    }
}

function Get-ScriptletListFiles {
    param(
        [string]$Root,
        [System.Collections.IList]$Warnings = $null
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'User Data folder is empty.' }
    if (-not (Test-Path $Root)) { throw "User Data folder not found: $Root" }

    $files = @()
    $componentDirs = @(Get-ChildItem -Path $Root -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^[a-z]{32}$' })
    foreach ($dir in $componentDirs) {
        try {
            $files += Get-ChildItem -Path $dir.FullName -Recurse -Filter 'list.txt' -File -ErrorAction Stop
        } catch {
            $warning = "Scriptlet scan skipped $($dir.FullName): $_"
            if ($Warnings) { [void]$Warnings.Add($warning) } else { Write-Log $warning 'WARN' }
        }
    }
    return @($files | Sort-Object FullName)
}

function Get-ScriptletRules {
    param(
        [string]$Root,
        [System.Collections.IList]$Warnings = $null
    )

    $records = New-Object System.Collections.Generic.List[object]
    $files = Get-ScriptletListFiles -Root $Root -Warnings $Warnings
    foreach ($file in $files) {
        try {
            $lineNo = 0
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                $lineNo++
                $record = ConvertTo-ScriptletRecord -File $file.FullName -Root $Root -Line $line -LineNumber $lineNo
                if ($record) { [void]$records.Add($record) }
            }
        } catch {
            $warning = "Scriptlet scan failed $($file.FullName): $_"
            if ($Warnings) { [void]$Warnings.Add($warning) } else { Write-Log $warning 'WARN' }
        }
    }
    return @($records.ToArray())
}

function Backup-ScriptletFile {
    param([string]$File)

    if (-not (Test-Path $File)) { throw "Scriptlet list file not found: $File" }
    $backup = "$File.bfo-backup"
    if (-not (Test-Path $backup)) {
        Copy-Item -LiteralPath $File -Destination $backup -Force
        Write-Log "Scriptlet backup created: $backup" 'OK'
    }
    return $backup
}

function Test-ScriptletAdvancedWriteAllowed {
    if (-not $script:ChkScriptletAdvanced -or -not $script:ChkScriptletAdvanced.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "编辑 Brave 内部过滤列表已被禁用。`r`n`r`n请先在【默认脚本规则】选项卡中勾选【高级编辑模式】。",
            '脚本规则管理器',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }

    $braveProcesses = @(Get-Process -Name brave -ErrorAction SilentlyContinue)
    if ($braveProcesses.Count -gt 0) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "检测到 Brave 浏览器当前正在运行（共 $($braveProcesses.Count) 个进程）。`r`n`r`n为确保安全修改，建议先关闭 Brave。是否仍要继续？",
            '脚本规则管理器',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -ne 'Yes') { return $false }
    }

    return $true
}

function Set-ScriptletRuleState {
    param(
        [object[]]$Records,
        [bool]$Enable,
        [bool]$AffectDuplicates
    )

    if (-not $Records -or $Records.Count -eq 0) { return 0 }
    $changed = 0
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $byFile = $Records | Group-Object File

    foreach ($group in $byFile) {
        $file = $group.Name
        [void](Backup-ScriptletFile -File $file)
        $lines = [System.IO.File]::ReadAllLines($file)

        if ($AffectDuplicates) {
            $wanted = @{}
            foreach ($record in $group.Group) { $wanted[$record.Rule] = $true }
            for ($i = 0; $i -lt $lines.Length; $i++) {
                $original = Get-ScriptletRuleFromLine -Line $lines[$i]
                if (-not $original -or -not $wanted.ContainsKey($original)) { continue }

                $disabledRule = Get-BfoDisabledScriptletRule -Line $lines[$i]
                if ($Enable -and $disabledRule) {
                    $lines[$i] = $disabledRule
                    $changed++
                } elseif (-not $Enable -and -not $disabledRule) {
                    $lines[$i] = "$($script:ScriptletDisablePrefix)$original"
                    $changed++
                }
            }
        } else {
            foreach ($record in $group.Group) {
                $idx = [int]$record.LineNumber - 1
                if ($idx -lt 0 -or $idx -ge $lines.Length) { continue }
                $original = Get-ScriptletRuleFromLine -Line $lines[$idx]
                if ($original -ne $record.Rule) { continue }

                $disabledRule = Get-BfoDisabledScriptletRule -Line $lines[$idx]
                if ($Enable -and $disabledRule) {
                    $lines[$idx] = $disabledRule
                    $changed++
                } elseif (-not $Enable -and -not $disabledRule) {
                    $lines[$idx] = "$($script:ScriptletDisablePrefix)$original"
                    $changed++
                }
            }
        }

        [System.IO.File]::WriteAllLines($file, [string[]]$lines, $utf8NoBom)
    }

    return $changed
}

function Restore-ScriptletBackup {
    param([string]$File)

    $backup = "$File.bfo-backup"
    if (-not (Test-Path $backup)) { throw "No backup exists for: $File" }
    Copy-Item -LiteralPath $backup -Destination $File -Force
}

function Restore-AllScriptletBackups {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path $Root)) { throw "User Data folder not found: $Root" }
    $backups = @(Get-ChildItem -Path $Root -Recurse -Filter 'list.txt.bfo-backup' -File -ErrorAction SilentlyContinue)
    $count = 0
    foreach ($backup in $backups) {
        $target = $backup.FullName.Substring(0, $backup.FullName.Length - '.bfo-backup'.Length)
        Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
        $count++
    }
    return $count
}

function Export-ScriptletDisabledPreferences {
    param([string]$File)

    $disabled = @($script:ScriptletRules | Where-Object { -not $_.Enabled } | Sort-Object Rule -Unique)
    $payload = [ordered]@{
        version       = '1.9'
        exported      = (Get-Date -Format 's')
        disabledRules = @(
            foreach ($r in $disabled) {
                [ordered]@{
                    rule      = $r.Rule
                    domain    = $r.Domain
                    scriptlet = $r.Scriptlet
                    source    = $r.Source
                }
            }
        )
    }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $File -Encoding UTF8
    return $disabled.Count
}

function Import-ScriptletPreferencesAndReapply {
    param([string]$PrefsFile, [string]$Root)

    if (-not (Test-Path $PrefsFile)) { throw "Preference file not found: $PrefsFile" }
    $prefs = Get-Content $PrefsFile -Raw | ConvertFrom-Json
    if (-not $prefs.disabledRules) { throw 'Preference file has no disabledRules array.' }

    $wanted = @{}
    foreach ($entry in $prefs.disabledRules) {
        if ($entry.rule) { $wanted["$($entry.rule)"] = $true }
    }
    if ($wanted.Count -eq 0) { return 0 }

    $changed = 0
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    foreach ($file in (Get-ScriptletListFiles -Root $Root)) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        $fileChanged = $false
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $original = Get-ScriptletRuleFromLine -Line $lines[$i]
            if (-not $original -or -not $wanted.ContainsKey($original)) { continue }
            if (Get-BfoDisabledScriptletRule -Line $lines[$i]) { continue }
            if (-not $fileChanged) {
                [void](Backup-ScriptletFile -File $file.FullName)
                $fileChanged = $true
            }
            $lines[$i] = "$($script:ScriptletDisablePrefix)$original"
            $changed++
        }
        if ($fileChanged) {
            [System.IO.File]::WriteAllLines($file.FullName, [string[]]$lines, $utf8NoBom)
        }
    }
    return $changed
}

function Resize-ScriptletColumns {
    if (-not $script:ScriptletList) { return }
    if ($script:ScriptletList.Columns.Count -lt 7) { return }

    $width = [Math]::Max(760, $script:ScriptletList.ClientSize.Width - 10)
    $pickWidth = 92
    $lineWidth = 55
    $flex = [Math]::Max(600, $width - $pickWidth - $lineWidth)
    $domainWidth = [Math]::Max(105, [int]($flex * 0.16))
    $scriptletWidth = [Math]::Max(115, [int]($flex * 0.17))
    $argsWidth = [Math]::Max(145, [int]($flex * 0.22))
    $sourceWidth = [Math]::Max(125, [int]($flex * 0.15))
    $rawWidth = [Math]::Max(170, $width - ($pickWidth + $domainWidth + $scriptletWidth + $argsWidth + $sourceWidth + $lineWidth + 4))

    $script:ScriptletList.Columns[0].Width = $pickWidth
    $script:ScriptletList.Columns[1].Width = $domainWidth
    $script:ScriptletList.Columns[2].Width = $scriptletWidth
    $script:ScriptletList.Columns[3].Width = $argsWidth
    $script:ScriptletList.Columns[4].Width = $sourceWidth
    $script:ScriptletList.Columns[5].Width = $lineWidth
    $script:ScriptletList.Columns[6].Width = $rawWidth
}

function Update-ScriptletStatusText {
    param([int]$Shown = -1)

    if (-not $script:LblScriptletStatus) { return }
    if ($Shown -lt 0) { $Shown = @($script:ScriptletVisibleRules).Count }

    $enabled = @($script:ScriptletRules | Where-Object { $_.Enabled }).Count
    $disabled = @($script:ScriptletRules | Where-Object { -not $_.Enabled }).Count
    $checked = $script:ScriptletCheckedKeys.Count
    $script:LblScriptletStatus.Text = "Showing $Shown / $($script:ScriptletRules.Count). Enabled: $enabled. Disabled: $disabled. Checked: $checked."
}

function Set-ScriptletUiBusy {
    param([bool]$Busy, [string]$Message = '')

    foreach ($control in @(
        $script:BtnScriptletScan,
        $script:BtnScriptletFilter,
        $script:BtnScriptletDisable,
        $script:BtnScriptletEnable,
        $script:BtnScriptletCheckVisible,
        $script:BtnScriptletClearChecks,
        $script:BtnScriptletImportPrefs
    )) {
        if ($control) { $control.Enabled = -not $Busy }
    }

    if ($script:LblScriptletStatus -and $Message) { $script:LblScriptletStatus.Text = $Message }
    if ($form) { $form.UseWaitCursor = $Busy }
    [System.Windows.Forms.Application]::DoEvents()
}

function Start-ScriptletFilterDelay {
    if ($script:ScriptletFilterTimer) {
        $script:ScriptletFilterTimer.Stop()
        $script:ScriptletFilterTimer.Start()
    } else {
        Update-ScriptletListView
    }
}

function Get-ScriptletRecordKey {
    param([object]$Record)

    if (-not $Record) { return $null }
    return ('{0}`t{1}' -f [string]$Record.File, [int]$Record.LineNumber)
}

function Test-ScriptletRecordChecked {
    param([object]$Record)

    $key = Get-ScriptletRecordKey -Record $Record
    return ($key -and $script:ScriptletCheckedKeys.ContainsKey($key))
}

function Set-ScriptletRecordChecked {
    param(
        [object]$Record,
        [bool]$Checked
    )

    $key = Get-ScriptletRecordKey -Record $Record
    if (-not $key) { return }

    if ($Checked) {
        $script:ScriptletCheckedKeys[$key] = $true
    } else {
        [void]$script:ScriptletCheckedKeys.Remove($key)
    }
}

function New-ScriptletListItem {
    param([object]$Record)

    $item = New-Object System.Windows.Forms.ListViewItem($(if ($Record.Enabled) { 'Enabled' } else { 'Disabled' }))
    [void]$item.SubItems.Add($Record.Domain)
    [void]$item.SubItems.Add($Record.Scriptlet)
    [void]$item.SubItems.Add($Record.Arguments)
    [void]$item.SubItems.Add("$($Record.Source) $($Record.Version)")
    [void]$item.SubItems.Add([string]$Record.LineNumber)
    [void]$item.SubItems.Add($Record.Rule)
    $item.Tag = $Record
    $item.Checked = Test-ScriptletRecordChecked -Record $Record
    if (-not $Record.Enabled) {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
    }
    return $item
}

function Stop-ScriptletRender {
    if ($script:ScriptletRenderTimer) { $script:ScriptletRenderTimer.Stop() }
    $script:ScriptletRenderState = $null
    $script:SuppressScriptletStatusEvents = $false
}

function Start-ScriptletRender {
    param([object[]]$Rows)

    if (-not $script:ScriptletList) { return }
    Stop-ScriptletRender
    Set-ScriptletUiBusy $true "Rendering 0 / $($Rows.Count) visible scriptlet row(s)..."
    Resize-ScriptletColumns

    $script:SuppressScriptletStatusEvents = $true
    $script:ScriptletList.BeginUpdate()
    try {
        $script:ScriptletList.Items.Clear()
    } finally {
        $script:ScriptletList.EndUpdate()
    }

    $script:ScriptletRenderState = [pscustomobject]@{
        Rows      = @($Rows)
        Index     = 0
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    if ($script:ScriptletProgress) {
        $script:ScriptletProgress.Visible = $true
        $script:ScriptletProgress.Style = 'Continuous'
        $script:ScriptletProgress.Value = 0
    }
    if ($script:LblScriptletStatus) {
        $script:LblScriptletStatus.Text = "Rendering 0 / $($Rows.Count) visible scriptlet row(s)..."
    }

    if ($Rows.Count -eq 0) {
        Stop-ScriptletRender
        if ($script:ScriptletProgress) { $script:ScriptletProgress.Value = 0 }
        Update-ScriptletStatusText -Shown 0
        Set-ScriptletUiBusy $false
        return
    }

    if (-not $script:ScriptletRenderTimer) {
        $script:ScriptletRenderTimer = New-Object System.Windows.Forms.Timer
        $script:ScriptletRenderTimer.Interval = 10
        $script:ScriptletRenderTimer.Add_Tick({ Step-ScriptletRender })
    }
    $script:ScriptletRenderTimer.Start()
}

function Step-ScriptletRender {
    $state = $script:ScriptletRenderState
    if (-not $state) {
        Stop-ScriptletRender
        return
    }

    $total = $state.Rows.Count
    if ($total -eq 0) {
        Stop-ScriptletRender
        Update-ScriptletStatusText -Shown 0
        return
    }

    $startTick = [Environment]::TickCount64
    $batch = New-Object System.Collections.Generic.List[System.Windows.Forms.ListViewItem]
    while ($state.Index -lt $total -and (([Environment]::TickCount64 - $startTick) -lt 25) -and $batch.Count -lt 400) {
        [void]$batch.Add((New-ScriptletListItem -Record $state.Rows[$state.Index]))
        $state.Index++
    }

    if ($batch.Count -gt 0) {
        $items = $batch.ToArray()
        $script:ScriptletList.BeginUpdate()
        try {
            $script:ScriptletList.Items.AddRange($items)
        } finally {
            $script:ScriptletList.EndUpdate()
        }
    }

    $percent = [int](($state.Index * 1000L) / [Math]::Max(1, $total))
    $percent = [Math]::Max(0, [Math]::Min(1000, $percent))
    if ($script:ScriptletProgress) { $script:ScriptletProgress.Value = $percent }
    if ($script:LblScriptletStatus) {
        $seconds = [Math]::Round($state.Stopwatch.Elapsed.TotalSeconds, 1)
        $script:LblScriptletStatus.Text = "Rendering $($state.Index) / $total visible scriptlet row(s)... ${seconds}s"
    }

    if ($state.Index -ge $total) {
        $elapsed = [Math]::Round($state.Stopwatch.Elapsed.TotalSeconds, 1)
        Stop-ScriptletRender
        if ($script:ScriptletProgress) { $script:ScriptletProgress.Value = 1000 }
        Update-ScriptletStatusText -Shown $total
        if ($script:LblScriptletStatus) {
            $script:LblScriptletStatus.Text += " Render completed in ${elapsed}s."
        }
        Set-ScriptletUiBusy $false
    }
}

function Update-ScriptletListView {
    if (-not $script:ScriptletList) { return }

    $query = if ($script:TxtScriptletSearch) { $script:TxtScriptletSearch.Text.Trim() } else { '' }
    $disabledOnly = ($script:ChkScriptletDisabledOnly -and $script:ChkScriptletDisabledOnly.Checked)
    $rows = @($script:ScriptletRules)
    if ($disabledOnly) { $rows = @($rows | Where-Object { -not $_.Enabled }) }
    if (-not [string]::IsNullOrWhiteSpace($query)) {
        $needle = $query.ToLowerInvariant()
        $rows = @($rows | Where-Object {
            ("$($_.Domain) $($_.Scriptlet) $($_.Arguments) $($_.Source) $($_.Rule) $($_.File)").ToLowerInvariant().Contains($needle)
        })
    }

    $script:ScriptletVisibleRules = $rows
    Start-ScriptletRender -Rows $rows
}

function Get-SelectedScriptletRecords {
    if (-not $script:ScriptletList) { return @() }
    $records = @()

    if ($script:ScriptletCheckedKeys.Count -gt 0) {
        foreach ($record in $script:ScriptletRules) {
            if (Test-ScriptletRecordChecked -Record $record) { $records += $record }
        }
        return $records
    }

    foreach ($item in $script:ScriptletList.SelectedItems) {
        if ($item.Tag) { $records += $item.Tag }
    }
    return $records
}

function Set-ScriptletVisibleChecks {
    param([bool]$Checked)

    if (-not $script:ScriptletList) { return }
    if ($Checked) {
        foreach ($record in $script:ScriptletVisibleRules) {
            Set-ScriptletRecordChecked -Record $record -Checked $true
        }
    } else {
        $script:ScriptletCheckedKeys.Clear()
    }

    $script:SuppressScriptletStatusEvents = $true
    $script:ScriptletList.BeginUpdate()
    try {
        foreach ($item in $script:ScriptletList.Items) {
            $item.Checked = Test-ScriptletRecordChecked -Record $item.Tag
        }
    } finally {
        $script:ScriptletList.EndUpdate()
        $script:SuppressScriptletStatusEvents = $false
    }
    Update-ScriptletStatusText
}

function Update-ScriptletScanProgress {
    param([string]$Message = '')

    $state = $script:ScriptletScanState
    if (-not $state) { return }

    $currentBytes = 0L
    if ($state.Reader -and $state.Reader.BaseStream) {
        try { $currentBytes = [int64]$state.Reader.BaseStream.Position } catch { $currentBytes = 0L }
    }
    $doneBytes = [Math]::Min([int64]$state.TotalBytes, [int64]($state.ProcessedBytes + $currentBytes))
    $percent = if ($state.TotalBytes -gt 0) { [int](($doneBytes * 1000L) / $state.TotalBytes) } else { 0 }
    $percent = [Math]::Max(0, [Math]::Min(1000, $percent))

    if ($script:ScriptletProgress) {
        $script:ScriptletProgress.Visible = $true
        $script:ScriptletProgress.Style = 'Continuous'
        $script:ScriptletProgress.Value = $percent
    }

    if ($script:LblScriptletStatus) {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            $fileName = if ($state.CurrentFile) { Split-Path $state.CurrentFile.FullName -Leaf } else { 'starting...' }
            $seconds = [Math]::Max(1, [int]$state.Stopwatch.Elapsed.TotalSeconds)
            $Message = "Scanning file $($state.FileIndex) / $($state.Files.Count): $fileName. Found $($state.Records.Count) rule(s). $([int]($percent / 10))%. ${seconds}s"
        }
        $script:LblScriptletStatus.Text = $Message
    }
}

function Stop-ScriptletScan {
    if ($script:ScriptletScanTimer) { $script:ScriptletScanTimer.Stop() }
    if ($script:ScriptletScanState -and $script:ScriptletScanState.Reader) {
        try { $script:ScriptletScanState.Reader.Dispose() } catch {}
    }
    $script:ScriptletScanState = $null
    Set-ScriptletUiBusy $false
}

function Complete-ScriptletScan {
    $state = $script:ScriptletScanState
    if (-not $state) { return }

    if ($script:ScriptletScanTimer) { $script:ScriptletScanTimer.Stop() }
    if ($state.Reader) {
        try { $state.Reader.Dispose() } catch {}
        $state.Reader = $null
    }
    $state.Stopwatch.Stop()

    $script:ScriptletRules = @($state.Records.ToArray())
    foreach ($warning in @($state.Warnings)) { Write-Log $warning 'WARN' }

    if ($script:ScriptletProgress) {
        $script:ScriptletProgress.Visible = $true
        $script:ScriptletProgress.Style = 'Continuous'
        $script:ScriptletProgress.Value = 1000
    }

    $elapsed = [Math]::Round($state.Stopwatch.Elapsed.TotalSeconds, 1)
    $root = $state.Root
    $script:ScriptletScanState = $null
    if ($script:LblScriptletStatus) {
        $script:LblScriptletStatus.Text = "Rendering $($script:ScriptletRules.Count) scriptlet row(s)..."
    }
    [System.Windows.Forms.Application]::DoEvents()
    Update-ScriptletListView
    Write-Log "Scriptlet scan complete: $($script:ScriptletRules.Count) rule(s) from $root in ${elapsed}s" 'OK'

    if ($script:LblScriptletStatus) {
        $script:LblScriptletStatus.Text += " Scan completed in ${elapsed}s."
    }
    if ($script:ScriptletRules.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No Brave scriptlet rules were found in:`r`n$root`r`n`r`nUse Browse if your Brave User Data folder lives somewhere else.",
            'Scriptlet manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

function Step-ScriptletScan {
    $state = $script:ScriptletScanState
    if (-not $state) {
        if ($script:ScriptletScanTimer) { $script:ScriptletScanTimer.Stop() }
        return
    }

    $startTick = [Environment]::TickCount64
    $linesThisTick = 0
    while ((([Environment]::TickCount64 - $startTick) -lt 35) -and ($linesThisTick -lt 2500)) {
        if (-not $state.Reader) {
            if ($state.FileIndex -ge $state.Files.Count) {
                Complete-ScriptletScan
                return
            }

            $file = $state.Files[$state.FileIndex]
            $state.FileIndex++
            $state.CurrentFile = $file
            $state.CurrentLine = 0
            try {
                $state.Reader = [System.IO.File]::OpenText($file.FullName)
            } catch {
                [void]$state.Warnings.Add("Scriptlet scan failed $($file.FullName): $_")
                $state.ProcessedBytes += [int64]$file.Length
                $state.Reader = $null
                continue
            }
        }

        try {
            $line = $state.Reader.ReadLine()
        } catch {
            [void]$state.Warnings.Add("Scriptlet scan failed $($state.CurrentFile.FullName): $_")
            try { $state.Reader.Dispose() } catch {}
            $state.ProcessedBytes += [int64]$state.CurrentFile.Length
            $state.Reader = $null
            continue
        }

        if ($null -eq $line) {
            try { $state.Reader.Dispose() } catch {}
            $state.ProcessedBytes += [int64]$state.CurrentFile.Length
            $state.Reader = $null
            continue
        }

        $state.CurrentLine++
        $linesThisTick++
        $record = ConvertTo-ScriptletRecord -File $state.CurrentFile.FullName -Root $state.Root -Line $line -LineNumber $state.CurrentLine
        if ($record) { [void]$state.Records.Add($record) }
    }

    Update-ScriptletScanProgress
}

function Invoke-ScriptletScan {
    $root = $script:TxtScriptletRoot.Text.Trim()
    if ($script:ScriptletScanState) {
        Write-Log 'Scriptlet scan is already running.' 'INFO'
        return
    }

    try {
        Set-ScriptletUiBusy $true 'Finding Brave scriptlet list files...'
        $warnings = New-Object System.Collections.ArrayList
        $files = @(Get-ScriptletListFiles -Root $root -Warnings $warnings)
        if ($files.Count -eq 0) {
            Set-ScriptletUiBusy $false
            if ($script:ScriptletProgress) { $script:ScriptletProgress.Value = 0 }
            [System.Windows.Forms.MessageBox]::Show(
                "No Brave filter-list files were found in:`r`n$root`r`n`r`nUse Browse if your Brave User Data folder lives somewhere else.",
                'Scriptlet manager',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }

        $totalBytes = [int64](@($files | Measure-Object Length -Sum).Sum)
        if ($totalBytes -lt 1) { $totalBytes = 1 }
        $script:ScriptletRules = @()
        $script:ScriptletVisibleRules = @()
        $script:ScriptletCheckedKeys.Clear()
        if ($script:ScriptletList) { $script:ScriptletList.Items.Clear() }

        $script:ScriptletScanState = [pscustomobject]@{
            Root           = $root
            Files          = $files
            FileIndex      = 0
            CurrentFile    = $null
            CurrentLine    = 0
            Reader         = $null
            ProcessedBytes = 0L
            TotalBytes     = $totalBytes
            Records        = (New-Object System.Collections.Generic.List[object])
            Warnings       = $warnings
            Stopwatch      = [System.Diagnostics.Stopwatch]::StartNew()
        }

        if ($script:ScriptletProgress) {
            $script:ScriptletProgress.Visible = $true
            $script:ScriptletProgress.Style = 'Continuous'
            $script:ScriptletProgress.Value = 0
        }
        Update-ScriptletScanProgress "Found $($files.Count) list file(s). Scanning in chunks..."
        Write-Log "Scriptlet scan started: $root ($($files.Count) list file(s), $([Math]::Round($totalBytes / 1MB, 2)) MB)" 'INFO'

        if (-not $script:ScriptletScanTimer) {
            $script:ScriptletScanTimer = New-Object System.Windows.Forms.Timer
            $script:ScriptletScanTimer.Interval = 15
            $script:ScriptletScanTimer.Add_Tick({ Step-ScriptletScan })
        }
        $script:ScriptletScanTimer.Start()
    } catch {
        Stop-ScriptletScan
        $script:ScriptletRules = @()
        Update-ScriptletListView
        Write-Log "Scriptlet scan failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show(
            "Could not scan scriptlets:`r`n$_`r`n`r`nUse Browse to point Brave-Free-Origin at the correct Brave User Data folder.",
            'Scriptlet manager',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}
#endregion

#region GUI Build -------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Brave Free Origin v1.11 - 免费解锁极简精简模式 (中文版)" 
$form.Size = New-Object System.Drawing.Size(1180, 900)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1080, 820)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$braveVer = Get-BraveVersion
$script:SuppressSelectionEvents = $false
$script:ActiveProfile = 'Custom'
$script:MinimalPolicies = @(
    'HardwareAccelerationModeEnabled',
    'BraveRewardsDisabled','BraveWalletDisabled','BraveVPNDisabled',
    'BraveAIChatEnabled','PasswordManagerEnabled'
)
$script:OriginPolicies = @(
    'HardwareAccelerationModeEnabled',
    'BraveAIChatEnabled',
    'BraveNewsDisabled',
    'BraveP3AEnabled',
    'BravePlaylistEnabled',
    'BraveRewardsDisabled',
    'BraveSpeedreaderEnabled',
    'BraveStatsPingEnabled',
    'BraveTalkDisabled',
    'BraveVPNDisabled',
    'BraveWalletDisabled',
    'BraveWaybackMachineEnabled',
    'BraveWebDiscoveryEnabled',
    'MetricsReportingEnabled',
    'TorDisabled',
    # Shields / privacy-engine policies - keeping ad-block ON is a *performance* win
    # (fewer requests, less DOM, less JS). It's also Brave's identity. Origin Mode
    # and everything that derives from it (Privacy + Boost) now enforces these.
    'DefaultBraveAdblockSetting',
    'DefaultBraveFingerprintingV2Setting',
    'DefaultBraveReferrersSetting',
    'BraveTrackingQueryParametersFilteringEnabled',
    'BraveDeAmpEnabled',
    'BraveDebouncingEnabled'
)
$script:PerformancePolicies = @(
    $script:OriginPolicies +
    @(
        'BackgroundModeEnabled',
        'BrowserLabsEnabled',
        'CloudPrintSubmitEnabled',
        'DiskCacheSize',
        'HardwareAccelerationModeEnabled',
        'HighEfficiencyModeEnabled',
        'HomepageIsNewTabPage',
        'HomepageLocation',
        'IPFSEnabled',
        'LiveCaptionEnabled',
        'MediaRouterEnabled',
        'NetworkPredictionOptions',
        'NewTabPageLocation',
        'NTPCustomBackgroundEnabled',
        'PromotionalTabsEnabled',
        'QuicAllowed',
        'ReadingListEnabled',
        'RestoreOnStartup',
        'WebRtcEventLogCollectionAllowed',
        'WebTorrentDisabled',
        'WelcomePageOnOSUpgradeEnabled'
    )
) | Select-Object -Unique
$script:MaxPrivacyPolicies = @(
    foreach ($cat in $script:Policies.Keys) {
        foreach ($policy in $script:Policies[$cat]) {
            if ($policy.MaxPrivacy) { $policy.Name }
        }
    }
) | Select-Object -Unique
$script:MaxPerformancePolicies = @(
    $script:MaxPrivacyPolicies +
    $script:PerformancePolicies +
    @(
        'BookmarkBarEnabled',
        'PromptForDownloadLocation',
        'ShowHomeButton',
        'SpellcheckEnabled'
    )
) | Select-Object -Unique
$script:ProfileDisplayNames = @{
    'Minimal'        = '快速轻度瘦身 (Quick Debloat)'
    'Recommended'    = '推荐配置 (Recommended)'
    'Origin'         = '极简 Origin 模式 (Origin Mode)'
    'Performance'    = '隐私 + 提速 (Privacy + Boost)'
    'MaxPerformance' = '极致性能模式 (Max Performance)'
    'MaxPrivacy'     = '极致隐私模式 (Max Privacy)'
    'None'           = '官方默认 / 清空 (Stock / None)'
    'CurrentState'   = '当前系统状态 (Current State)'
    'Custom'         = '自定义 (Custom)'
}
$script:ProfileDescriptions = @{
    'Minimal'      = '快速轻度瘦身。移除最显眼的商业推广附加功能，而不大幅改变浏览器行为。'
    'Recommended'  = '均衡的日常主力配置。兼顾优秀隐私保护与清爽界面，保持核心兼容性与媒体播放默认体验。'
    'Origin'       = '对标 2026年4月 Brave Origin 的极简构想：默认关闭 Leo AI、Rewards、钱包、VPN、新闻、Talk、Tor、时光机、Web Discovery 及相关统计。'
    'Performance'  = '隐私 + 提速。在 Origin 极简的基础上加入启动与延迟优化，适合在游戏、直播、音乐串流时使用更轻盈的浏览器。'
    'MaxPerformance' = '全能融合模式：集成 Origin 极简、隐私提速与强力隐私策略，并进一步精简界面。最贴近极客与游戏玩家的全开优化配置。'
    'MaxPrivacy'   = '强力锁定模式。提供极致隐私保护，但会禁用同步、登录、数据导入以及 Brave 更新服务。'
    'None'         = '官方默认状态。未选择任何策略，不对浏览器做强制策略约束。'
    'CurrentState' = '从本机注册表读取。展示当前系统上已生效的策略设置。'
    'Custom'       = '自由定制。使用下方各选项卡勾选组装您专属的 Brave 优化方案。'
}
$script:ProfileRisks = @{
    'Minimal'      = '低风险 (Low risk)'
    'Recommended'  = '低风险 (Low risk)'
    'Origin'       = '低风险 (Low risk)'
    'Performance'  = '中风险 (Medium risk)'
    'MaxPerformance' = '高风险 (High risk)'
    'MaxPrivacy'   = '高风险 (High risk)'
    'None'         = '无改动 (No changes)'
    'CurrentState' = '仅读取 (Read only)'
    'Custom'       = '取决于您的选择'
}

function Get-PresetPayload {
    param([string]$Preset)

    # Hosts groups: only auto-tick a group when the corresponding feature is
    # ALSO disabled by policy in this preset. No orphan blocks.
    $hostsAlwaysSafe   = @('Brave P3A 遥测','Brave 实验配置 (Variations)','Brave 使用统计 Ping','网络探索 (Web Discovery)')
    $hostsRewards      = @('Brave Rewards / BAT 打赏')
    $hostsNews         = @('Brave News 新闻 CDN')
    $hostsComponents   = @('组件更新 (Component Updates)')

    switch ($Preset) {
        'Recommended' {
            return @{
                Policies = @(
                    foreach ($cat in $script:Policies.Keys) {
                        foreach ($policy in $script:Policies[$cat]) {
                            if ($policy.Recommended) { $policy.Name }
                        }
                    }
                )
                Tasks    = @($script:ScheduledTasks.Name)
                Services = @()
                Hosts    = $hostsAlwaysSafe + $hostsRewards + $hostsNews
            }
        }
        'MaxPrivacy' {
            return @{
                Policies = @($script:MaxPrivacyPolicies)
                Tasks    = @($script:ScheduledTasks.Name)
                Services = @($script:Services.Name)
                Hosts    = $hostsAlwaysSafe + $hostsRewards + $hostsNews + $hostsComponents
            }
        }
        'Minimal' {
            return @{
                Policies = @($script:MinimalPolicies)
                Tasks    = @()
                Services = @()
                Hosts    = $hostsAlwaysSafe + $hostsRewards   # Quick disables Rewards, leaves News on
            }
        }
        'Origin' {
            return @{
                Policies = @($script:OriginPolicies)
                Tasks    = @()
                Services = @()
                Hosts    = $hostsAlwaysSafe + $hostsRewards + $hostsNews   # Origin disables both
            }
        }
        'Performance' {
            return @{
                Policies = @($script:PerformancePolicies)
                Tasks    = @($script:ScheduledTasks.Name)
                Services = @()
                Hosts    = $hostsAlwaysSafe + $hostsRewards + $hostsNews
            }
        }
        'MaxPerformance' {
            return @{
                Policies = @($script:MaxPerformancePolicies)
                Tasks    = @($script:ScheduledTasks.Name)
                Services = @($script:Services.Name)
                Hosts    = $hostsAlwaysSafe + $hostsRewards + $hostsNews + $hostsComponents
            }
        }
        default {
            return @{
                Policies = @()
                Tasks    = @()
                Services = @()
                Hosts    = @()
            }
        }
    }
}

function Update-SelectionSummary {
    if (-not $script:ModeLabel) { return }

    $selectedPolicies = @($script:CheckBoxes | Where-Object { $_.Checked })
    $selectedTasks = @($script:TaskCheckBoxes | Where-Object { $_.Checked })
    $selectedServices = @($script:ServiceCheckBoxes | Where-Object { $_.Checked })
    $modeKey = if ([string]::IsNullOrWhiteSpace($script:ActiveProfile)) { 'Custom' } else { $script:ActiveProfile }
    $modeLabel = if ($script:ProfileDisplayNames.ContainsKey($modeKey)) { $script:ProfileDisplayNames[$modeKey] } else { $modeKey }

    $script:ModeLabel.Text = "当前模式: $modeLabel"
    $script:SelectionLabel.Text = "策略: $($selectedPolicies.Count) / $($script:CheckBoxes.Count)"
    $script:SystemLabel.Text = "系统: $($selectedTasks.Count) 任务, $($selectedServices.Count) 服务"
    $script:RiskLabel.Text = "风险评估: $($script:ProfileRisks[$modeKey])"
    $script:ModeDescription.Text = $script:ProfileDescriptions[$modeKey]
}

function Set-CustomMode {
    if ($script:SuppressSelectionEvents) { return }
    $script:ActiveProfile = 'Custom'
    Update-SelectionSummary
}

function Apply-Preset {
    param([string]$Preset)

    $payload = Get-PresetPayload -Preset $Preset
    $script:SuppressSelectionEvents = $true

    foreach ($cb in $script:CheckBoxes) {
        $policyName = $cb.Tag.Policy.Name
        $cb.Checked = $payload.Policies -contains $policyName
    }
    foreach ($cb in $script:TaskCheckBoxes) {
        $cb.Checked = $payload.Tasks -contains $cb.Tag.Name
    }
    foreach ($cb in $script:ServiceCheckBoxes) {
        $cb.Checked = $payload.Services -contains $cb.Tag.Name
    }
    # Hosts checkboxes (created later in the GUI; guard if not yet built)
    if ($script:HostsCheckBoxes) {
        foreach ($cb in $script:HostsCheckBoxes) {
            $cb.Checked = $payload.Hosts -contains $cb.Tag.Name
        }
    }

    $script:SuppressSelectionEvents = $false
    $script:ActiveProfile = $Preset
    Update-SelectionSummary
    $presetLabel = if ($script:ProfileDisplayNames.ContainsKey($Preset)) { $script:ProfileDisplayNames[$Preset] } else { $Preset }
    Write-Log "Loaded mode: $presetLabel"
}

# Header panel
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 112
$header.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Brave Free Origin'
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$titleLabel.Location = New-Object System.Drawing.Point(18, 10)
$titleLabel.AutoSize = $true
$header.Controls.Add($titleLabel)

$subLabel = New-Object System.Windows.Forms.Label
$subLabel.Text = "剔除 Brave 内置的 AI、加密钱包、VPN、推广资讯与后台干扰，打造更轻量、低占用的桌面浏览器。" 
$subLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$subLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$subLabel.Location = New-Object System.Drawing.Point(20, 43)
$subLabel.Size = New-Object System.Drawing.Size(760, 18)
$header.Controls.Add($subLabel)

$metaLabel = New-Object System.Windows.Forms.Label
$metaLabel.Text = "已检测到 Brave 版本: $braveVer" 
$metaLabel.ForeColor = [System.Drawing.Color]::LightSteelBlue
$metaLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$metaLabel.Location = New-Object System.Drawing.Point(20, 70)
$metaLabel.Size = New-Object System.Drawing.Size(280, 18)
$header.Controls.Add($metaLabel)

# Channel selector (multi-channel support)
$detectedChannels = Get-DetectedChannels
$channelLabel = New-Object System.Windows.Forms.Label
$channelLabel.Text = '目标版本频道:' 
$channelLabel.ForeColor = [System.Drawing.Color]::LightSteelBlue
$channelLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$channelLabel.Location = New-Object System.Drawing.Point(310, 70)
$channelLabel.Size = New-Object System.Drawing.Size(95, 18)
$header.Controls.Add($channelLabel)

$script:ChannelCombo = New-Object System.Windows.Forms.ComboBox
$script:ChannelCombo.Location = New-Object System.Drawing.Point(405, 67)
$script:ChannelCombo.Size = New-Object System.Drawing.Size(220, 22)
$script:ChannelCombo.DropDownStyle = 'DropDownList'
$script:ChannelCombo.FlatStyle = 'Flat'
foreach ($name in $script:Channels.Keys) {
    $marker = if ($detectedChannels -contains $name) { '  (已安装)' } else { '  (未安装)' }
    [void]$script:ChannelCombo.Items.Add("$name$marker")
}
if ($detectedChannels.Count -gt 1) { [void]$script:ChannelCombo.Items.Add('所有已安装版本 (All installed)') }
$script:ChannelCombo.SelectedIndex = 0
$header.Controls.Add($script:ChannelCombo)

$script:TargetPathLabel = New-Object System.Windows.Forms.Label
$script:TargetPathLabel.Text = "-> $($script:Channels['Stable'].Path)"
$script:TargetPathLabel.ForeColor = [System.Drawing.Color]::Gray
$script:TargetPathLabel.Font = New-Object System.Drawing.Font('Consolas', 8)
$script:TargetPathLabel.Location = New-Object System.Drawing.Point(635, 70)
$script:TargetPathLabel.Size = New-Object System.Drawing.Size(500, 18)
$header.Controls.Add($script:TargetPathLabel)

$script:ChannelCombo.Add_SelectedIndexChanged({
    $sel = $script:ChannelCombo.SelectedItem.ToString()
    if ($sel -eq '所有已安装版本 (All installed)') {
        $script:TargetChannels = Get-DetectedChannels
        if ($script:TargetChannels.Count -eq 0) { $script:TargetChannels = @('Stable') }
        $script:BravePolicyPath = $script:Channels[$script:TargetChannels[0]].Path
        $script:TargetPathLabel.Text = "-> $($script:TargetChannels -join ', ') ($($script:TargetChannels.Count) hives)"
    } else {
        $name = ($sel -split '  ')[0]
        $script:TargetChannels = @($name)
        $script:BravePolicyPath = $script:Channels[$name].Path
        $script:TargetPathLabel.Text = "-> $($script:Channels[$name].Path)"
    }
    Write-Log "Target channel(s): $($script:TargetChannels -join ', ')"
})

$originNote = New-Object System.Windows.Forms.Label
$originNote.Text = '背景说明：Brave 于 2026 年 4 月公布了极简 Origin 模式构想并将其列为付费功能。本项目通过本地策略免费实现相同的效果。' 
$originNote.ForeColor = [System.Drawing.Color]::FromArgb(255, 212, 153)
$originNote.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$originNote.Location = New-Object System.Drawing.Point(20, 88)
$originNote.Size = New-Object System.Drawing.Size(950, 18)
$header.Controls.Add($originNote)

$form.Controls.Add($header)

# Tooltip
$tt = New-Object System.Windows.Forms.ToolTip
$tt.AutoPopDelay = 30000
$tt.InitialDelay = 300
$tt.ReshowDelay  = 300

# Mode deck
$modePanel = New-Object System.Windows.Forms.Panel
$modePanel.Location = New-Object System.Drawing.Point(10, 122)
$modePanel.Size = New-Object System.Drawing.Size(1145, 126)
$modePanel.Anchor = 'Top, Left, Right'
$modePanel.BackColor = [System.Drawing.Color]::White
$modePanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($modePanel)

$modeIntro = New-Object System.Windows.Forms.Label
$modeIntro.Text = '点击上方一键预设模式，或在下方各选项卡中按需微调具体策略。' 
$modeIntro.Location = New-Object System.Drawing.Point(14, 10)
$modeIntro.Size = New-Object System.Drawing.Size(620, 18)
$modeIntro.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$modePanel.Controls.Add($modeIntro)

$buttonSpecs = @(
    @{Text='快速瘦身';   Mode='Minimal';        X=14;  Width=104; Color=[System.Drawing.Color]::FromArgb(235, 236, 240)},
    @{Text='推荐配置';   Mode='Recommended';    X=124; Width=104; Color=[System.Drawing.Color]::FromArgb(220, 238, 222)},
    @{Text='Origin 模式';Mode='Origin';         X=234; Width=104; Color=[System.Drawing.Color]::FromArgb(250, 232, 210)},
    @{Text='隐私 + 提速';Mode='Performance';    X=344; Width=108; Color=[System.Drawing.Color]::FromArgb(218, 231, 248)},
    @{Text='极致性能';   Mode='MaxPerformance'; X=458; Width=118; Color=[System.Drawing.Color]::FromArgb(255, 224, 224)},
    @{Text='极致隐私';   Mode='MaxPrivacy';     X=582; Width=100; Color=[System.Drawing.Color]::FromArgb(229, 220, 240)},
    @{Text='恢复默认';   Mode='None';           X=688; Width=100; Color=[System.Drawing.Color]::FromArgb(241, 241, 241)}
)
foreach ($spec in $buttonSpecs) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $spec.Text
    $btn.Size = New-Object System.Drawing.Size($spec.Width, 30)
    $btn.Location = New-Object System.Drawing.Point($spec.X, 34)
    $btn.BackColor = $spec.Color
    $btn.Tag = $spec.Mode
    $btn.Add_Click({ Apply-Preset $this.Tag })
    $modePanel.Controls.Add($btn)
}

$script:ModeLabel = New-Object System.Windows.Forms.Label
$script:ModeLabel.Location = New-Object System.Drawing.Point(14, 78)
$script:ModeLabel.Size = New-Object System.Drawing.Size(170, 18)
$script:ModeLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$modePanel.Controls.Add($script:ModeLabel)

$script:SelectionLabel = New-Object System.Windows.Forms.Label
$script:SelectionLabel.Location = New-Object System.Drawing.Point(190, 78)
$script:SelectionLabel.Size = New-Object System.Drawing.Size(150, 18)
$modePanel.Controls.Add($script:SelectionLabel)

$script:SystemLabel = New-Object System.Windows.Forms.Label
$script:SystemLabel.Location = New-Object System.Drawing.Point(346, 78)
$script:SystemLabel.Size = New-Object System.Drawing.Size(190, 18)
$modePanel.Controls.Add($script:SystemLabel)

$script:RiskLabel = New-Object System.Windows.Forms.Label
$script:RiskLabel.Location = New-Object System.Drawing.Point(542, 78)
$script:RiskLabel.Size = New-Object System.Drawing.Size(130, 18)
$script:RiskLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$modePanel.Controls.Add($script:RiskLabel)

$script:ModeDescription = New-Object System.Windows.Forms.Label
$script:ModeDescription.Location = New-Object System.Drawing.Point(678, 72)
$script:ModeDescription.Size = New-Object System.Drawing.Size(440, 36)
$script:ModeDescription.ForeColor = [System.Drawing.Color]::DimGray
$script:ModeDescription.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$modePanel.Controls.Add($script:ModeDescription)

# Tab control
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 256)
$tabs.Size = New-Object System.Drawing.Size(1145, 410)
$tabs.Anchor = 'Top, Left, Right, Bottom'
$form.Controls.Add($tabs)

# Track every checkbox so we can iterate on apply/reset
$script:CheckBoxes = @()
# Maps a policy Name -> its value-picker ComboBox (only for policies that
# define a Choices map, e.g. HardwareAccelerationModeEnabled). Used by
# refresh/import so the picker reflects the real registry value.
$script:PolicyCombos = @{}

foreach ($cat in $script:Policies.Keys) {
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $cat
    $tab.AutoScroll = $true
    $tab.BackColor = [System.Drawing.Color]::White

    $selAll = New-Object System.Windows.Forms.LinkLabel
    $selAll.Text = '全选 (Select all)'
    $selAll.Location = New-Object System.Drawing.Point(10, 8)
    $selAll.AutoSize = $true
    $selAll.Tag = $cat
    $selAll.Add_LinkClicked({
        $myCat = $this.Tag
        $script:SuppressSelectionEvents = $true
        foreach ($cb in $script:CheckBoxes) {
            if ($cb.Tag.Category -eq $myCat) { $cb.Checked = $true }
        }
        $script:SuppressSelectionEvents = $false
        $script:ActiveProfile = 'Custom'
        Update-SelectionSummary
    })
    $tab.Controls.Add($selAll)

    $selNone = New-Object System.Windows.Forms.LinkLabel
    $selNone.Text = '全不选 (Select none)'
    $selNone.Location = New-Object System.Drawing.Point(140, 8)
    $selNone.AutoSize = $true
    $selNone.Tag = $cat
    $selNone.Add_LinkClicked({
        $myCat = $this.Tag
        $script:SuppressSelectionEvents = $true
        foreach ($cb in $script:CheckBoxes) {
            if ($cb.Tag.Category -eq $myCat) { $cb.Checked = $false }
        }
        $script:SuppressSelectionEvents = $false
        $script:ActiveProfile = 'Custom'
        Update-SelectionSummary
    })
    $tab.Controls.Add($selNone)

    $y = 35
    foreach ($p in $script:Policies[$cat]) {
        $cb = New-Object System.Windows.Forms.CheckBox
        # Policies with a Choices map show a dropdown for the value instead of a
        # fixed "=> N", so keep their label short; others keep the classic text.
        if ($p.Choices) { $cb.Text = $p.Name } else { $cb.Text = "$($p.Name)    =>  $($p.ApplyValue)" }
        $cb.Location = New-Object System.Drawing.Point(15, $y)
        $cb.Size = New-Object System.Drawing.Size(($(if ($p.Choices) { 300 } else { 450 })), 20)
        $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
        $cb.Tag = @{Policy = $p; Category = $cat}
        $cb.Add_CheckedChanged({ Set-CustomMode })
        $tt.SetToolTip($cb, $p.Description)
        $tab.Controls.Add($cb)
        $script:CheckBoxes += $cb

        # Value picker for choice-based policies. Selecting an item rewrites the
        # policy's ApplyValue in place, so every downstream path (apply, verify,
        # export) automatically uses the chosen value with no extra plumbing.
        if ($p.Choices) {
            $combo = New-Object System.Windows.Forms.ComboBox
            $combo.DropDownStyle = 'DropDownList'
            $combo.Location = New-Object System.Drawing.Point(320, ($y - 1))
            $combo.Size = New-Object System.Drawing.Size(140, 22)
            $combo.Font = New-Object System.Drawing.Font('Consolas', 9)
            foreach ($label in $p.Choices.Keys) { [void]$combo.Items.Add($label) }
            # Preselect the label whose value matches the current ApplyValue.
            foreach ($label in $p.Choices.Keys) {
                if ("$($p.Choices[$label])" -eq "$($p.ApplyValue)") { $combo.SelectedItem = $label; break }
            }
            if ($combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }
            $combo.Tag = $p
            $combo.Add_SelectedIndexChanged({
                $pol = $this.Tag
                if ($this.SelectedItem -and $pol.Choices.Contains("$($this.SelectedItem)")) {
                    $pol.ApplyValue = $pol.Choices["$($this.SelectedItem)"]
                }
                Set-CustomMode
            })
            $tt.SetToolTip($combo, $p.Description)
            $tab.Controls.Add($combo)
            $script:PolicyCombos[$p.Name] = $combo
        }

        $desc = New-Object System.Windows.Forms.Label
        $desc.Text = $p.Description
        $desc.Location = New-Object System.Drawing.Point(475, ($y + 2))
        $desc.Size = New-Object System.Drawing.Size(630, 30)
        $desc.ForeColor = [System.Drawing.Color]::DimGray
        $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $tab.Controls.Add($desc)

        $y += 28
    }
    $tabs.TabPages.Add($tab)
}

# ---- System tab: scheduled tasks + services --------------------------------
$sysTab = New-Object System.Windows.Forms.TabPage
$sysTab.Text = '系统组件 (任务 / 服务)'
$sysTab.AutoScroll = $true
$sysTab.BackColor = [System.Drawing.Color]::White

$sysIntro = New-Object System.Windows.Forms.Label
$sysIntro.Text = "后台更新程序主要影响 隐私+提速、极致性能 和 极致隐私 模式。禁用服务具有最高风险，因为这会阻止 Brave 自动更新。" 
$sysIntro.Location = New-Object System.Drawing.Point(10, 8)
$sysIntro.Size = New-Object System.Drawing.Size(1080, 30)
$sysIntro.ForeColor = [System.Drawing.Color]::FromArgb(120, 50, 50)
$sysTab.Controls.Add($sysIntro)

$script:TaskCheckBoxes = @()
$y = 50
$taskHdr = New-Object System.Windows.Forms.Label
$taskHdr.Text = '计划任务 (Scheduled Tasks)'
$taskHdr.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$taskHdr.Location = New-Object System.Drawing.Point(10, $y)
$taskHdr.AutoSize = $true
$sysTab.Controls.Add($taskHdr)
$y += 28
foreach ($t in $script:ScheduledTasks) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $t.Name
    $cb.Location = New-Object System.Drawing.Point(15, $y)
    $cb.Size = New-Object System.Drawing.Size(450, 20)
    $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.Tag = $t
    $cb.Add_CheckedChanged({ Set-CustomMode })
    $tt.SetToolTip($cb, $t.Description)
    $sysTab.Controls.Add($cb)
    $script:TaskCheckBoxes += $cb

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = $t.Description
    $desc.Location = New-Object System.Drawing.Point(475, ($y + 2))
    $desc.Size = New-Object System.Drawing.Size(630, 30)
    $desc.ForeColor = [System.Drawing.Color]::DimGray
    $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $sysTab.Controls.Add($desc)
    $y += 28
}

$script:ServiceCheckBoxes = @()
$y += 15
$svcHdr = New-Object System.Windows.Forms.Label
$svcHdr.Text = 'Windows 系统服务 (Windows Services)'
$svcHdr.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$svcHdr.Location = New-Object System.Drawing.Point(10, $y)
$svcHdr.AutoSize = $true
$sysTab.Controls.Add($svcHdr)
$y += 28
foreach ($s in $script:Services) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $s.Name
    $cb.Location = New-Object System.Drawing.Point(15, $y)
    $cb.Size = New-Object System.Drawing.Size(450, 20)
    $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.Tag = $s
    $cb.Add_CheckedChanged({ Set-CustomMode })
    $tt.SetToolTip($cb, $s.Description)
    $sysTab.Controls.Add($cb)
    $script:ServiceCheckBoxes += $cb

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = $s.Description
    $desc.Location = New-Object System.Drawing.Point(475, ($y + 2))
    $desc.Size = New-Object System.Drawing.Size(630, 30)
    $desc.ForeColor = [System.Drawing.Color]::DimGray
    $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $sysTab.Controls.Add($desc)
    $y += 28
}

$tabs.TabPages.Add($sysTab)

# ---- Hosts blocklist tab (v1.5) --------------------------------------------
# Independent from the main Apply button - has its own Apply/Remove inside the tab.
# Sentinel-tagged so revert is surgical. Auto-backs up hosts file before any write.
$hostsTab = New-Object System.Windows.Forms.TabPage
$hostsTab.Text = 'Hosts 域名屏蔽 (DNS 级别)'
$hostsTab.AutoScroll = $true
$hostsTab.BackColor = [System.Drawing.Color]::White

$hostsIntro = New-Object System.Windows.Forms.Label
$hostsIntro.Text = "可选的第二道防线：在 C:\Windows\System32\drivers\etc\hosts 中将 Brave 遥测域名解析定向到 0.0.0.0。即使某次更新绕过了策略，网络请求也会直接失败。采用专属标记块确保干净回滚。备份保存在 Documents\Brave-Free-Origin-Backups 目录中。" 
$hostsIntro.Location = New-Object System.Drawing.Point(10, 8)
$hostsIntro.Size = New-Object System.Drawing.Size(1100, 36)
$hostsIntro.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
$hostsTab.Controls.Add($hostsIntro)

$hostsWarn = New-Object System.Windows.Forms.Label
$hostsWarn.Text = '【注意】此功能独立于主界面的【应用到 Brave】按钮。请使用本选项卡内的按钮应用或清除 hosts 屏蔽规则。' 
$hostsWarn.Location = New-Object System.Drawing.Point(10, 44)
$hostsWarn.Size = New-Object System.Drawing.Size(1100, 18)
$hostsWarn.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 30)
$hostsWarn.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
$hostsTab.Controls.Add($hostsWarn)

$script:HostsCheckBoxes = @()
$y = 70
foreach ($block in $script:HostsBlocks) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = "$($block.Name)  [$($block.Domains.Count) 个域名]" 
    $cb.Location = New-Object System.Drawing.Point(15, $y)
    $cb.Size = New-Object System.Drawing.Size(360, 20)
    $cb.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $cb.Checked = [bool]$block.Recommended
    $cb.Tag = $block
    $tt.SetToolTip($cb, $block.Description)
    $hostsTab.Controls.Add($cb)
    $script:HostsCheckBoxes += $cb

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = $block.Description
    $desc.Location = New-Object System.Drawing.Point(385, ($y + 2))
    $desc.Size = New-Object System.Drawing.Size(720, 32)
    $desc.ForeColor = [System.Drawing.Color]::DimGray
    $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $hostsTab.Controls.Add($desc)

    $domLabel = New-Object System.Windows.Forms.Label
    $domLabel.Text = ($block.Domains -join ', ')
    $domLabel.Location = New-Object System.Drawing.Point(35, ($y + 22))
    $domLabel.Size = New-Object System.Drawing.Size(340, 16)
    $domLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $domLabel.Font = New-Object System.Drawing.Font('Consolas', 8)
    $hostsTab.Controls.Add($domLabel)

    $y += 44
}

$btnApplyHosts = New-Object System.Windows.Forms.Button
$btnApplyHosts.Text = '应用 Hosts 屏蔽'
$btnApplyHosts.Size = New-Object System.Drawing.Size(160, 30)
$btnApplyHosts.Location = New-Object System.Drawing.Point(15, ($y + 10))
$btnApplyHosts.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 63)
$btnApplyHosts.ForeColor = [System.Drawing.Color]::White
$btnApplyHosts.Add_Click({
    $domains = @()
    foreach ($cb in $script:HostsCheckBoxes) {
        if ($cb.Checked) { $domains += $cb.Tag.Domains }
    }
    if ($domains.Count -eq 0) {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            '未勾选任何分组。这将移除现有的 hosts 屏蔽块（如果存在）。是否继续？',
            'Hosts 域名屏蔽', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
    } else {
        $msg = "即将向以下文件写入 $($domains.Count) 条屏蔽条目：`r`n$($script:HostsFile)`r`n`r`n写入前将自动保存带时间戳的备份文件。是否继续？"
        $ans = [System.Windows.Forms.MessageBox]::Show($msg, 'Hosts 域名屏蔽', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
    }
    try {
        Set-HostsBlockDomains -Domains $domains
        [System.Windows.Forms.MessageBox]::Show("Hosts 文件已更新。已屏蔽 $($domains.Count) 个域名。`r`nDNS 缓存已成功刷新。", '完成', 'OK', 'Information') | Out-Null
    } catch {
        Write-Log "Hosts apply failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Failed: $_", 'Error', 'OK', 'Error') | Out-Null
    }
})
$hostsTab.Controls.Add($btnApplyHosts)

$btnClearHosts = New-Object System.Windows.Forms.Button
$btnClearHosts.Text = '清除 Hosts 屏蔽块'
$btnClearHosts.Size = New-Object System.Drawing.Size(160, 30)
$btnClearHosts.Location = New-Object System.Drawing.Point(185, ($y + 10))
$btnClearHosts.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "是否从 hosts 文件中移除 Brave-Free-Origin 专属屏蔽标记块？`r`n（您的其他 hosts 自定义条目不会受任何影响。）",
        'Hosts 域名屏蔽', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        Clear-HostsBlock
        foreach ($cb in $script:HostsCheckBoxes) { $cb.Checked = $false }
        [System.Windows.Forms.MessageBox]::Show('专属屏蔽标记块已成功移除。', '完成', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed: $_", 'Error', 'OK', 'Error') | Out-Null
    }
})
$hostsTab.Controls.Add($btnClearHosts)

$btnLoadHosts = New-Object System.Windows.Forms.Button
$btnLoadHosts.Text = '读取当前 Hosts 状态'
$btnLoadHosts.Size = New-Object System.Drawing.Size(160, 30)
$btnLoadHosts.Location = New-Object System.Drawing.Point(355, ($y + 10))
$btnLoadHosts.Add_Click({
    $current = Get-HostsCurrentDomains
    foreach ($cb in $script:HostsCheckBoxes) {
        $blockDomains = $cb.Tag.Domains
        $allPresent = $true
        foreach ($d in $blockDomains) { if ($current -notcontains $d) { $allPresent = $false; break } }
        $cb.Checked = $allPresent
    }
    Write-Log "Hosts state loaded: $($current.Count) domain(s) currently blocked."
})
$hostsTab.Controls.Add($btnLoadHosts)

$btnPreviewHosts = New-Object System.Windows.Forms.Button
$btnPreviewHosts.Text = '预览 Hosts 变更'
$btnPreviewHosts.Size = New-Object System.Drawing.Size(130, 30)
$btnPreviewHosts.Location = New-Object System.Drawing.Point(525, ($y + 10))
$btnPreviewHosts.Add_Click({
    Show-TextReport -Title 'Preview hosts blocklist' -Text (New-HostsPlanReport) -DefaultFileName "brave-free-origin-hosts-preview-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
})
$hostsTab.Controls.Add($btnPreviewHosts)

$btnOpenHosts = New-Object System.Windows.Forms.Button
$btnOpenHosts.Text = '打开 hosts 文件'
$btnOpenHosts.Size = New-Object System.Drawing.Size(140, 30)
$btnOpenHosts.Location = New-Object System.Drawing.Point(665, ($y + 10))
$btnOpenHosts.Add_Click({ Start-Process notepad.exe $script:HostsFile })
$hostsTab.Controls.Add($btnOpenHosts)

$tabs.TabPages.Add($hostsTab)

# ---- Default scriptlets tab (v1.11) ----------------------------------------
# Advanced, optional, and deliberately separate from presets/main Apply.
# Scans Brave component filter lists, displays ##+js(...) rules, and can
# comment/uncomment rules with a BFO marker after explicit user opt-in.
$scriptletsTab = New-Object System.Windows.Forms.TabPage
$scriptletsTab.Text = '默认脚本规则 (高级)'
$scriptletsTab.AutoScroll = $true
$scriptletsTab.BackColor = [System.Drawing.Color]::White

$scriptletIntro = New-Object System.Windows.Forms.Label
$scriptletIntro.Text = "可选高级工具：查看 Brave 组件过滤列表中内置的广告拦截注入脚本规则 (##+js)。此处修改仅限手动执行，绝不包含在预设中，也绝不会被【应用到 Brave】触发。" 
$scriptletIntro.Location = New-Object System.Drawing.Point(10, 8)
$scriptletIntro.Size = New-Object System.Drawing.Size(1100, 34)
$scriptletIntro.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
$scriptletsTab.Controls.Add($scriptletIntro)

$scriptletRisk = New-Object System.Windows.Forms.Label
$scriptletRisk.Text = "风险提示：禁用 scriptlet 脚本规则可能会破坏广告拦截、防烦人弹窗、Cookie 授权弹窗处理、视频网站功能或网站兼容性。Brave 更新可能会替换组件版本；如有需要可导出已禁用偏好并在更新后重新应用。" 
$scriptletRisk.Location = New-Object System.Drawing.Point(10, 38)
$scriptletRisk.Size = New-Object System.Drawing.Size(1100, 34)
$scriptletRisk.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 30)
$scriptletRisk.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
$scriptletsTab.Controls.Add($scriptletRisk)

$lblScriptletRoot = New-Object System.Windows.Forms.Label
$lblScriptletRoot.Text = 'Brave 用户数据目录:'
$lblScriptletRoot.Location = New-Object System.Drawing.Point(10, 80)
$lblScriptletRoot.Size = New-Object System.Drawing.Size(145, 18)
$scriptletsTab.Controls.Add($lblScriptletRoot)

$script:TxtScriptletRoot = New-Object System.Windows.Forms.TextBox
$script:TxtScriptletRoot.Location = New-Object System.Drawing.Point(155, 76)
$script:TxtScriptletRoot.Size = New-Object System.Drawing.Size(560, 22)
$script:TxtScriptletRoot.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:TxtScriptletRoot.Text = Get-ScriptletDefaultRoot
$scriptletsTab.Controls.Add($script:TxtScriptletRoot)

$btnScriptletAutoRoot = New-Object System.Windows.Forms.Button
$btnScriptletAutoRoot.Text = '自动路径'
$btnScriptletAutoRoot.Size = New-Object System.Drawing.Size(85, 26)
$btnScriptletAutoRoot.Location = New-Object System.Drawing.Point(725, 74)
$btnScriptletAutoRoot.Add_Click({
    $script:TxtScriptletRoot.Text = Get-ScriptletDefaultRoot
    Write-Log "Scriptlet User Data path set to: $($script:TxtScriptletRoot.Text)"
})
$scriptletsTab.Controls.Add($btnScriptletAutoRoot)

$btnScriptletBrowse = New-Object System.Windows.Forms.Button
$btnScriptletBrowse.Text = '浏览...'
$btnScriptletBrowse.Size = New-Object System.Drawing.Size(85, 26)
$btnScriptletBrowse.Location = New-Object System.Drawing.Point(815, 74)
$btnScriptletBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select Brave User Data folder'
    if (Test-Path $script:TxtScriptletRoot.Text) { $dlg.SelectedPath = $script:TxtScriptletRoot.Text }
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:TxtScriptletRoot.Text = $dlg.SelectedPath
        Write-Log "Scriptlet User Data path set manually: $($dlg.SelectedPath)"
    }
})
$scriptletsTab.Controls.Add($btnScriptletBrowse)

$script:BtnScriptletScan = New-Object System.Windows.Forms.Button
$script:BtnScriptletScan.Text = '扫描'
$script:BtnScriptletScan.Size = New-Object System.Drawing.Size(80, 26)
$script:BtnScriptletScan.Location = New-Object System.Drawing.Point(905, 74)
$script:BtnScriptletScan.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 63)
$script:BtnScriptletScan.ForeColor = [System.Drawing.Color]::White
$script:BtnScriptletScan.Add_Click({ Invoke-ScriptletScan })
$scriptletsTab.Controls.Add($script:BtnScriptletScan)

$btnScriptletOpenFolder = New-Object System.Windows.Forms.Button
$btnScriptletOpenFolder.Text = '打开目录'
$btnScriptletOpenFolder.Size = New-Object System.Drawing.Size(95, 26)
$btnScriptletOpenFolder.Location = New-Object System.Drawing.Point(990, 74)
$btnScriptletOpenFolder.Add_Click({
    if (Test-Path $script:TxtScriptletRoot.Text) { Start-Process explorer.exe $script:TxtScriptletRoot.Text }
    else { [System.Windows.Forms.MessageBox]::Show('Folder not found. Use Browse to choose the correct Brave User Data folder.', 'Scriptlet manager', 'OK', 'Warning') | Out-Null }
})
$scriptletsTab.Controls.Add($btnScriptletOpenFolder)

$lblScriptletSearch = New-Object System.Windows.Forms.Label
$lblScriptletSearch.Text = '搜索/筛选:'
$lblScriptletSearch.Location = New-Object System.Drawing.Point(10, 112)
$lblScriptletSearch.Size = New-Object System.Drawing.Size(85, 18)
$scriptletsTab.Controls.Add($lblScriptletSearch)

$script:TxtScriptletSearch = New-Object System.Windows.Forms.TextBox
$script:TxtScriptletSearch.Location = New-Object System.Drawing.Point(95, 108)
$script:TxtScriptletSearch.Size = New-Object System.Drawing.Size(360, 22)
$script:TxtScriptletSearch.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:TxtScriptletSearch.Add_TextChanged({ Start-ScriptletFilterDelay })
$script:TxtScriptletSearch.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') {
        if ($script:ScriptletFilterTimer) { $script:ScriptletFilterTimer.Stop() }
        Update-ScriptletListView
        $_.SuppressKeyPress = $true
    }
})
$scriptletsTab.Controls.Add($script:TxtScriptletSearch)

$script:ScriptletFilterTimer = New-Object System.Windows.Forms.Timer
$script:ScriptletFilterTimer.Interval = 250
$script:ScriptletFilterTimer.Add_Tick({
    $script:ScriptletFilterTimer.Stop()
    Update-ScriptletListView
})

$script:BtnScriptletFilter = New-Object System.Windows.Forms.Button
$script:BtnScriptletFilter.Text = '筛选'
$script:BtnScriptletFilter.Size = New-Object System.Drawing.Size(75, 26)
$script:BtnScriptletFilter.Location = New-Object System.Drawing.Point(465, 106)
$script:BtnScriptletFilter.Add_Click({
    if ($script:ScriptletFilterTimer) { $script:ScriptletFilterTimer.Stop() }
    Update-ScriptletListView
})
$scriptletsTab.Controls.Add($script:BtnScriptletFilter)

$script:ChkScriptletDisabledOnly = New-Object System.Windows.Forms.CheckBox
$script:ChkScriptletDisabledOnly.Text = '仅显示被本工具禁用的规则'
$script:ChkScriptletDisabledOnly.Location = New-Object System.Drawing.Point(550, 110)
$script:ChkScriptletDisabledOnly.Size = New-Object System.Drawing.Size(190, 20)
$script:ChkScriptletDisabledOnly.Add_CheckedChanged({ Update-ScriptletListView })
$scriptletsTab.Controls.Add($script:ChkScriptletDisabledOnly)

$script:ChkScriptletAdvanced = New-Object System.Windows.Forms.CheckBox
$script:ChkScriptletAdvanced.Text = '高级编辑模式 (允许修改 list.txt 文件)'
$script:ChkScriptletAdvanced.Location = New-Object System.Drawing.Point(755, 110)
$script:ChkScriptletAdvanced.Size = New-Object System.Drawing.Size(330, 20)
$script:ChkScriptletAdvanced.ForeColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
$scriptletsTab.Controls.Add($script:ChkScriptletAdvanced)

$script:ScriptletList = New-Object System.Windows.Forms.ListView
$script:ScriptletList.Location = New-Object System.Drawing.Point(10, 140)
$script:ScriptletList.Size = New-Object System.Drawing.Size(1110, 190)
$script:ScriptletList.View = 'Details'
$script:ScriptletList.FullRowSelect = $true
$script:ScriptletList.GridLines = $true
$script:ScriptletList.MultiSelect = $true
$script:ScriptletList.HideSelection = $false
$script:ScriptletList.CheckBoxes = $true
$script:ScriptletList.Anchor = 'Top, Left, Right'
$script:ScriptletList.Add_SizeChanged({ Resize-ScriptletColumns })
$script:ScriptletList.Add_ItemChecked({
    param($sender, $eventArgs)

    if (-not $script:SuppressScriptletStatusEvents) {
        Set-ScriptletRecordChecked -Record $eventArgs.Item.Tag -Checked $eventArgs.Item.Checked
        Update-ScriptletStatusText
    }
})
[void]$script:ScriptletList.Columns.Add('状态 (Status)', 105)
[void]$script:ScriptletList.Columns.Add('域名 (Domain)', 180)
[void]$script:ScriptletList.Columns.Add('脚本 (Scriptlet)', 190)
[void]$script:ScriptletList.Columns.Add('参数 (Arguments)', 260)
[void]$script:ScriptletList.Columns.Add('来源 / 版本', 180)
[void]$script:ScriptletList.Columns.Add('行号', 55)
[void]$script:ScriptletList.Columns.Add('原始规则 (Raw rule)', 520)
$scriptletsTab.Controls.Add($script:ScriptletList)

$script:LblScriptletStatus = New-Object System.Windows.Forms.Label
$script:LblScriptletStatus.Text = '点击【扫描】以分析 Brave 用户数据目录中的内置 scriptlet 脚本规则。'
$script:LblScriptletStatus.Location = New-Object System.Drawing.Point(10, 336)
$script:LblScriptletStatus.Size = New-Object System.Drawing.Size(520, 18)
$script:LblScriptletStatus.ForeColor = [System.Drawing.Color]::DimGray
$scriptletsTab.Controls.Add($script:LblScriptletStatus)

$script:ScriptletProgress = New-Object System.Windows.Forms.ProgressBar
$script:ScriptletProgress.Location = New-Object System.Drawing.Point(545, 336)
$script:ScriptletProgress.Size = New-Object System.Drawing.Size(575, 16)
$script:ScriptletProgress.Minimum = 0
$script:ScriptletProgress.Maximum = 1000
$script:ScriptletProgress.Value = 0
$script:ScriptletProgress.Style = 'Continuous'
$script:ScriptletProgress.Anchor = 'Top, Left, Right'
$scriptletsTab.Controls.Add($script:ScriptletProgress)

$script:ChkScriptletAffectDuplicates = New-Object System.Windows.Forms.CheckBox
$script:ChkScriptletAffectDuplicates.Text = '同时修改同文件中的重复原始规则'
$script:ChkScriptletAffectDuplicates.Checked = $true
$script:ChkScriptletAffectDuplicates.Location = New-Object System.Drawing.Point(10, 360)
$script:ChkScriptletAffectDuplicates.Size = New-Object System.Drawing.Size(270, 20)
$tt.SetToolTip($script:ChkScriptletAffectDuplicates, 'Brave lists can contain the same scriptlet rule multiple times. Leave this on unless you only want the exact selected line.')
$scriptletsTab.Controls.Add($script:ChkScriptletAffectDuplicates)

$script:BtnScriptletCheckVisible = New-Object System.Windows.Forms.Button
$script:BtnScriptletCheckVisible.Text = '勾选当前筛选结果'
$script:BtnScriptletCheckVisible.Size = New-Object System.Drawing.Size(125, 26)
$script:BtnScriptletCheckVisible.Location = New-Object System.Drawing.Point(290, 356)
$script:BtnScriptletCheckVisible.Add_Click({ Set-ScriptletVisibleChecks $true })
$tt.SetToolTip($script:BtnScriptletCheckVisible, 'Checks every row matching the active search/show filters, including rows not currently painted in the table.')
$scriptletsTab.Controls.Add($script:BtnScriptletCheckVisible)

$script:BtnScriptletClearChecks = New-Object System.Windows.Forms.Button
$script:BtnScriptletClearChecks.Text = '清除所有勾选'
$script:BtnScriptletClearChecks.Size = New-Object System.Drawing.Size(105, 26)
$script:BtnScriptletClearChecks.Location = New-Object System.Drawing.Point(425, 356)
$script:BtnScriptletClearChecks.Add_Click({ Set-ScriptletVisibleChecks $false })
$scriptletsTab.Controls.Add($script:BtnScriptletClearChecks)

$script:BtnScriptletDisable = New-Object System.Windows.Forms.Button
$script:BtnScriptletDisable.Text = '禁用已勾选规则'
$script:BtnScriptletDisable.Size = New-Object System.Drawing.Size(125, 28)
$script:BtnScriptletDisable.Location = New-Object System.Drawing.Point(10, 388)
$script:BtnScriptletDisable.BackColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
$script:BtnScriptletDisable.ForeColor = [System.Drawing.Color]::White
$script:BtnScriptletDisable.Add_Click({
    $records = @(Get-SelectedScriptletRecords)
    if ($records.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Check or select one or more scriptlet rules first.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    if (-not (Test-ScriptletAdvancedWriteAllowed)) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Disable $($records.Count) checked/selected scriptlet rule(s)?`r`n`r`nThis comments rules with: $($script:ScriptletDisablePrefix)`r`nBackups are created as list.txt.bfo-backup before the first edit.",
        'Scriptlet manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    try {
        $changed = Set-ScriptletRuleState -Records $records -Enable:$false -AffectDuplicates:$script:ChkScriptletAffectDuplicates.Checked
        Write-Log "Scriptlets disabled: $changed line(s)." 'OK'
        Invoke-ScriptletScan
    } catch {
        Write-Log "Scriptlet disable failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Disable failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($script:BtnScriptletDisable)

$script:BtnScriptletEnable = New-Object System.Windows.Forms.Button
$script:BtnScriptletEnable.Text = '启用已勾选规则'
$script:BtnScriptletEnable.Size = New-Object System.Drawing.Size(120, 28)
$script:BtnScriptletEnable.Location = New-Object System.Drawing.Point(145, 388)
$script:BtnScriptletEnable.Add_Click({
    $records = @(Get-SelectedScriptletRecords)
    if ($records.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Check or select one or more scriptlet rules first.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    if (-not (Test-ScriptletAdvancedWriteAllowed)) { return }
    try {
        $changed = Set-ScriptletRuleState -Records $records -Enable:$true -AffectDuplicates:$script:ChkScriptletAffectDuplicates.Checked
        Write-Log "Scriptlets enabled: $changed line(s)." 'OK'
        Invoke-ScriptletScan
    } catch {
        Write-Log "Scriptlet enable failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Enable failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($script:BtnScriptletEnable)

$btnScriptletDetails = New-Object System.Windows.Forms.Button
$btnScriptletDetails.Text = '查看选中规则详情'
$btnScriptletDetails.Size = New-Object System.Drawing.Size(115, 28)
$btnScriptletDetails.Location = New-Object System.Drawing.Point(275, 388)
$btnScriptletDetails.Add_Click({
    $records = @(Get-SelectedScriptletRecords)
    if ($records.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Select a scriptlet rule first.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    $report = New-Object System.Text.StringBuilder
    foreach ($r in $records) {
        [void]$report.AppendLine("Enabled: $($r.Enabled)")
        [void]$report.AppendLine("Domain: $($r.Domain)")
        [void]$report.AppendLine("Scriptlet: $($r.Scriptlet)")
        [void]$report.AppendLine("Arguments: $($r.Arguments)")
        [void]$report.AppendLine("Source: $($r.Source) $($r.Version)")
        [void]$report.AppendLine("File: $($r.File)")
        [void]$report.AppendLine("Line: $($r.LineNumber)")
        [void]$report.AppendLine("Rule: $($r.Rule)")
        [void]$report.AppendLine('')
    }
    Show-TextReport -Title 'Selected scriptlet rule(s)' -Text ($report.ToString()) -DefaultFileName "brave-free-origin-scriptlet-details-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
})
$scriptletsTab.Controls.Add($btnScriptletDetails)

$btnScriptletBackupAll = New-Object System.Windows.Forms.Button
$btnScriptletBackupAll.Text = '备份所有规则列表'
$btnScriptletBackupAll.Size = New-Object System.Drawing.Size(120, 28)
$btnScriptletBackupAll.Location = New-Object System.Drawing.Point(400, 388)
$btnScriptletBackupAll.Add_Click({
    try {
        $files = @($script:ScriptletRules | Select-Object -ExpandProperty File -Unique)
        if ($files.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Scan first; no scriptlet list files are loaded.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
        foreach ($file in $files) { [void](Backup-ScriptletFile -File $file) }
        [System.Windows.Forms.MessageBox]::Show("Backups checked/created for $($files.Count) list file(s).", 'Scriptlet manager', 'OK', 'Information') | Out-Null
    } catch {
        Write-Log "Scriptlet backup failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Backup failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($btnScriptletBackupAll)

$btnScriptletRestoreSelected = New-Object System.Windows.Forms.Button
$btnScriptletRestoreSelected.Text = '从备份还原选中文件'
$btnScriptletRestoreSelected.Size = New-Object System.Drawing.Size(145, 28)
$btnScriptletRestoreSelected.Location = New-Object System.Drawing.Point(530, 388)
$btnScriptletRestoreSelected.Add_Click({
    $records = @(Get-SelectedScriptletRecords)
    if ($records.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Select a rule from the file you want to restore.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    if (-not (Test-ScriptletAdvancedWriteAllowed)) { return }
    $files = @($records | Select-Object -ExpandProperty File -Unique)
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Restore $($files.Count) selected list file(s) from .bfo-backup?`r`nThis discards BFO scriptlet edits in those file(s).",
        'Scriptlet manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    try {
        foreach ($file in $files) { Restore-ScriptletBackup -File $file }
        Write-Log "Restored $($files.Count) scriptlet list file(s) from backup." 'OK'
        Invoke-ScriptletScan
    } catch {
        Write-Log "Scriptlet restore selected failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Restore failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($btnScriptletRestoreSelected)

$btnScriptletRestoreAll = New-Object System.Windows.Forms.Button
$btnScriptletRestoreAll.Text = '还原所有备份列表'
$btnScriptletRestoreAll.Size = New-Object System.Drawing.Size(140, 28)
$btnScriptletRestoreAll.Location = New-Object System.Drawing.Point(685, 388)
$btnScriptletRestoreAll.Add_Click({
    if (-not (Test-ScriptletAdvancedWriteAllowed)) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Restore every list.txt.bfo-backup under:`r`n$($script:TxtScriptletRoot.Text)`r`n`r`nThis discards all BFO scriptlet edits in backed-up lists. Continue?",
        'Scriptlet manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    try {
        $count = Restore-AllScriptletBackups -Root $script:TxtScriptletRoot.Text.Trim()
        Write-Log "Restored $count scriptlet backup file(s)." 'OK'
        Invoke-ScriptletScan
    } catch {
        Write-Log "Scriptlet restore all failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Restore all failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($btnScriptletRestoreAll)

$btnScriptletExportCsv = New-Object System.Windows.Forms.Button
$btnScriptletExportCsv.Text = '导出可见规则为 CSV'
$btnScriptletExportCsv.Size = New-Object System.Drawing.Size(130, 28)
$btnScriptletExportCsv.Location = New-Object System.Drawing.Point(835, 388)
$btnScriptletExportCsv.Add_Click({
    if (-not $script:ScriptletVisibleRules -or $script:ScriptletVisibleRules.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Nothing visible to export. Scan or change the filter first.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'CSV (*.csv)|*.csv'
    $sfd.FileName = "brave-free-origin-scriptlets-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    if ($sfd.ShowDialog() -ne 'OK') { return }
    $script:ScriptletVisibleRules |
        Select-Object Enabled,Domain,Scriptlet,Arguments,Source,Version,ComponentId,File,LineNumber,Rule |
        Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
    Write-Log "Scriptlet CSV exported: $($sfd.FileName)" 'OK'
})
$scriptletsTab.Controls.Add($btnScriptletExportCsv)

$btnScriptletExportPrefs = New-Object System.Windows.Forms.Button
$btnScriptletExportPrefs.Text = '导出已禁用偏好'
$btnScriptletExportPrefs.Size = New-Object System.Drawing.Size(150, 28)
$btnScriptletExportPrefs.Location = New-Object System.Drawing.Point(10, 424)
$btnScriptletExportPrefs.Add_Click({
    if (-not $script:ScriptletRules -or $script:ScriptletRules.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Scan first; there are no scriptlet rules loaded.', 'Scriptlet manager', 'OK', 'Information') | Out-Null; return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'Scriptlet preferences (*.json)|*.json'
    $sfd.FileName = "brave-free-origin-disabled-scriptlets-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    if ($sfd.ShowDialog() -ne 'OK') { return }
    try {
        $count = Export-ScriptletDisabledPreferences -File $sfd.FileName
        Write-Log "Disabled scriptlet prefs exported: $count rule(s)." 'OK'
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Export failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($btnScriptletExportPrefs)

$script:BtnScriptletImportPrefs = New-Object System.Windows.Forms.Button
$script:BtnScriptletImportPrefs.Text = '导入并重新应用偏好'
$script:BtnScriptletImportPrefs.Size = New-Object System.Drawing.Size(165, 28)
$script:BtnScriptletImportPrefs.Location = New-Object System.Drawing.Point(170, 424)
$script:BtnScriptletImportPrefs.Add_Click({
    if (-not (Test-ScriptletAdvancedWriteAllowed)) { return }
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'Scriptlet preferences (*.json)|*.json'
    if ($ofd.ShowDialog() -ne 'OK') { return }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Reapply disabled scriptlet preferences to the current component lists under:`r`n$($script:TxtScriptletRoot.Text)`r`n`r`nThis comments active rules whose raw text matches the preference file. Continue?",
        'Scriptlet manager',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    try {
        $changed = Import-ScriptletPreferencesAndReapply -PrefsFile $ofd.FileName -Root $script:TxtScriptletRoot.Text.Trim()
        Write-Log "Reapplied disabled scriptlet prefs: $changed line(s)." 'OK'
        Invoke-ScriptletScan
    } catch {
        Write-Log "Scriptlet preference reapply failed: $_" 'ERR'
        [System.Windows.Forms.MessageBox]::Show("Reapply failed:`r`n$_", 'Scriptlet manager', 'OK', 'Error') | Out-Null
    }
})
$scriptletsTab.Controls.Add($script:BtnScriptletImportPrefs)

$scriptletFooter = New-Object System.Windows.Forms.Label
$scriptletFooter.Text = '提示：若扫描未发现规则，请使用【浏览...】选择 Brave 个人资料目录下的 User Data 文件夹。仅当勾选【高级编辑模式】时才允许修改。' 
$scriptletFooter.Location = New-Object System.Drawing.Point(350, 429)
$scriptletFooter.Size = New-Object System.Drawing.Size(760, 32)
$scriptletFooter.ForeColor = [System.Drawing.Color]::DimGray
$scriptletFooter.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$scriptletsTab.Controls.Add($scriptletFooter)

$tabs.TabPages.Add($scriptletsTab)

# ---- Search & Startup tab (v1.6) -------------------------------------------
# Three independent, opt-in sections. Each has its own "Override" checkbox.
# Off by default: Brave's user-chosen search engine and startup behavior stay
# untouched unless the user actively ticks an override.
$searchTab = New-Object System.Windows.Forms.TabPage
$searchTab.Text = '搜索与启动设置'
$searchTab.AutoScroll = $true
$searchTab.BackColor = [System.Drawing.Color]::White

$searchIntro = New-Object System.Windows.Forms.Label
$searchIntro.Text = '设置地址栏搜索引擎，以及在 Brave 启动或打开新标签页时显示的内容。每个版块彼此独立，仅在勾选对应启用框时生效。取消勾选并应用即可移除覆盖。' 
$searchIntro.Location = New-Object System.Drawing.Point(10, 8)
$searchIntro.Size = New-Object System.Drawing.Size(1100, 36)
$searchIntro.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
$searchTab.Controls.Add($searchIntro)

# --- Section 1: Default search engine ---
$secSearch = New-Object System.Windows.Forms.GroupBox
$secSearch.Text = '默认搜索引擎（地址栏 / Omnibox）'
$secSearch.Location = New-Object System.Drawing.Point(10, 50)
$secSearch.Size = New-Object System.Drawing.Size(1110, 110)
$secSearch.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$searchTab.Controls.Add($secSearch)

$script:ChkSearchOverride = New-Object System.Windows.Forms.CheckBox
$script:ChkSearchOverride.Text = '强制指定默认搜索引擎 (写入 DefaultSearchProvider* 策略)'
$script:ChkSearchOverride.Location = New-Object System.Drawing.Point(15, 22)
$script:ChkSearchOverride.Size = New-Object System.Drawing.Size(530, 20)
$script:ChkSearchOverride.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$secSearch.Controls.Add($script:ChkSearchOverride)

$lblEngine = New-Object System.Windows.Forms.Label
$lblEngine.Text = '搜索引擎:'
$lblEngine.Location = New-Object System.Drawing.Point(35, 50)
$lblEngine.Size = New-Object System.Drawing.Size(60, 18)
$lblEngine.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$secSearch.Controls.Add($lblEngine)

$script:CmbSearchEngine = New-Object System.Windows.Forms.ComboBox
$script:CmbSearchEngine.Location = New-Object System.Drawing.Point(95, 47)
$script:CmbSearchEngine.Size = New-Object System.Drawing.Size(200, 22)
$script:CmbSearchEngine.DropDownStyle = 'DropDownList'
foreach ($name in $script:SearchEngines.Keys) { [void]$script:CmbSearchEngine.Items.Add($name) }
$script:CmbSearchEngine.SelectedIndex = 0
$secSearch.Controls.Add($script:CmbSearchEngine)

$lblCustomSearch = New-Object System.Windows.Forms.Label
$lblCustomSearch.Text = '自定义搜索 URL:'
$lblCustomSearch.Location = New-Object System.Drawing.Point(310, 50)
$lblCustomSearch.Size = New-Object System.Drawing.Size(115, 18)
$lblCustomSearch.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$secSearch.Controls.Add($lblCustomSearch)

$script:TxtCustomSearchUrl = New-Object System.Windows.Forms.TextBox
$script:TxtCustomSearchUrl.Location = New-Object System.Drawing.Point(425, 47)
$script:TxtCustomSearchUrl.Size = New-Object System.Drawing.Size(370, 22)
$script:TxtCustomSearchUrl.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:TxtCustomSearchUrl.Enabled = $false
$secSearch.Controls.Add($script:TxtCustomSearchUrl)

$searchHelp = New-Object System.Windows.Forms.Label
$searchHelp.Text = '自定义 URL 必须包含 {searchTerms} 作为搜索词占位符。示例：https://my-searx/search?q={searchTerms}' 
$searchHelp.Location = New-Object System.Drawing.Point(35, 78)
$searchHelp.Size = New-Object System.Drawing.Size(900, 18)
$searchHelp.ForeColor = [System.Drawing.Color]::DimGray
$searchHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$secSearch.Controls.Add($searchHelp)

$script:CmbSearchEngine.Add_SelectedIndexChanged({
    $isCustom = ($script:CmbSearchEngine.SelectedItem -eq '自定义 (Custom)...')
    $script:TxtCustomSearchUrl.Enabled = $isCustom
})

# --- Section 2: New tab page ---
$secNtp = New-Object System.Windows.Forms.GroupBox
$secNtp.Text = '新标签页 (New Tab Page)'
$secNtp.Location = New-Object System.Drawing.Point(10, 168)
$secNtp.Size = New-Object System.Drawing.Size(1110, 90)
$secNtp.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$searchTab.Controls.Add($secNtp)

$script:ChkNtpOverride = New-Object System.Windows.Forms.CheckBox
$script:ChkNtpOverride.Text = '覆盖新标签页 (写入 NewTabPageLocation 策略)'
$script:ChkNtpOverride.Location = New-Object System.Drawing.Point(15, 22)
$script:ChkNtpOverride.Size = New-Object System.Drawing.Size(450, 20)
$script:ChkNtpOverride.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$secNtp.Controls.Add($script:ChkNtpOverride)

$lblNtpDest = New-Object System.Windows.Forms.Label
$lblNtpDest.Text = '打开页面:'
$lblNtpDest.Location = New-Object System.Drawing.Point(35, 50)
$lblNtpDest.Size = New-Object System.Drawing.Size(50, 18)
$secNtp.Controls.Add($lblNtpDest)

$script:CmbNtpDest = New-Object System.Windows.Forms.ComboBox
$script:CmbNtpDest.Location = New-Object System.Drawing.Point(85, 47)
$script:CmbNtpDest.Size = New-Object System.Drawing.Size(310, 22)
$script:CmbNtpDest.DropDownStyle = 'DropDownList'
foreach ($name in $script:DestinationOptions.Keys) {
    if ($name -ne '默认新标签页 (不覆盖)') { [void]$script:CmbNtpDest.Items.Add($name) }
}
$script:CmbNtpDest.SelectedIndex = 0
$secNtp.Controls.Add($script:CmbNtpDest)

$lblNtpCustom = New-Object System.Windows.Forms.Label
$lblNtpCustom.Text = '自定义 URL:'
$lblNtpCustom.Location = New-Object System.Drawing.Point(410, 50)
$lblNtpCustom.Size = New-Object System.Drawing.Size(80, 18)
$secNtp.Controls.Add($lblNtpCustom)

$script:TxtNtpCustomUrl = New-Object System.Windows.Forms.TextBox
$script:TxtNtpCustomUrl.Location = New-Object System.Drawing.Point(490, 47)
$script:TxtNtpCustomUrl.Size = New-Object System.Drawing.Size(305, 22)
$script:TxtNtpCustomUrl.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:TxtNtpCustomUrl.Enabled = $false
$secNtp.Controls.Add($script:TxtNtpCustomUrl)

$script:CmbNtpDest.Add_SelectedIndexChanged({
    $isCustom = ($script:CmbNtpDest.SelectedItem -eq '自定义网址 (Custom URL)...')
    $script:TxtNtpCustomUrl.Enabled = $isCustom
})

# --- Section 3: Startup behavior ---
$secStartup = New-Object System.Windows.Forms.GroupBox
$secStartup.Text = '启动行为 (启动 Brave 时打开的内容)'
$secStartup.Location = New-Object System.Drawing.Point(10, 266)
$secStartup.Size = New-Object System.Drawing.Size(1110, 110)
$secStartup.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$searchTab.Controls.Add($secStartup)

$script:ChkStartupOverride = New-Object System.Windows.Forms.CheckBox
$script:ChkStartupOverride.Text = '覆盖启动行为 (写入 RestoreOnStartup 与 RestoreOnStartupURLs 策略)'
$script:ChkStartupOverride.Location = New-Object System.Drawing.Point(15, 22)
$script:ChkStartupOverride.Size = New-Object System.Drawing.Size(550, 20)
$script:ChkStartupOverride.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$secStartup.Controls.Add($script:ChkStartupOverride)

$lblStartMode = New-Object System.Windows.Forms.Label
$lblStartMode.Text = '启动模式:'
$lblStartMode.Location = New-Object System.Drawing.Point(35, 50)
$lblStartMode.Size = New-Object System.Drawing.Size(50, 18)
$secStartup.Controls.Add($lblStartMode)

$script:CmbStartupMode = New-Object System.Windows.Forms.ComboBox
$script:CmbStartupMode.Location = New-Object System.Drawing.Point(85, 47)
$script:CmbStartupMode.Size = New-Object System.Drawing.Size(310, 22)
$script:CmbStartupMode.DropDownStyle = 'DropDownList'
foreach ($name in $script:StartupModes.Keys) { [void]$script:CmbStartupMode.Items.Add($name) }
$script:CmbStartupMode.SelectedIndex = 0
$secStartup.Controls.Add($script:CmbStartupMode)

$lblStartUrl = New-Object System.Windows.Forms.Label
$lblStartUrl.Text = '网址列表:'
$lblStartUrl.Location = New-Object System.Drawing.Point(410, 50)
$lblStartUrl.Size = New-Object System.Drawing.Size(60, 18)
$secStartup.Controls.Add($lblStartUrl)

$script:TxtStartupUrl = New-Object System.Windows.Forms.TextBox
$script:TxtStartupUrl.Location = New-Object System.Drawing.Point(470, 47)
$script:TxtStartupUrl.Size = New-Object System.Drawing.Size(325, 22)
$script:TxtStartupUrl.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:TxtStartupUrl.Enabled = $false
$secStartup.Controls.Add($script:TxtStartupUrl)

$startupHelp = New-Object System.Windows.Forms.Label
$startupHelp.Text = '选择【特定网页或一组网页】时，多个网址请用英文逗号分隔，每个网址将在独立标签页中打开。' 
$startupHelp.Location = New-Object System.Drawing.Point(35, 78)
$startupHelp.Size = New-Object System.Drawing.Size(900, 18)
$startupHelp.ForeColor = [System.Drawing.Color]::DimGray
$startupHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$secStartup.Controls.Add($startupHelp)

$script:CmbStartupMode.Add_SelectedIndexChanged({
    $sel = $script:CmbStartupMode.SelectedItem
    $mode = $script:StartupModes[$sel]
    $script:TxtStartupUrl.Enabled = ($mode.UsesURL -and -not $mode.FixedURL)
})

# Conflict note
$conflictNote = New-Object System.Windows.Forms.Label
$conflictNote.Text = "说明：此选项卡将在【性能与启动】选项卡之后处理，因此会直接覆盖其中设置的 NewTabPageLocation / HomepageLocation / RestoreOnStartup 值。取消勾选并应用即可恢复原策略或 Brave 默认行为。" 
$conflictNote.Location = New-Object System.Drawing.Point(10, 384)
$conflictNote.Size = New-Object System.Drawing.Size(1100, 36)
$conflictNote.ForeColor = [System.Drawing.Color]::FromArgb(120, 60, 30)
$conflictNote.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$searchTab.Controls.Add($conflictNote)

# --- Section 4: Extensions (manual installs, no force-push) -----------------
$secExt = New-Object System.Windows.Forms.GroupBox
$secExt.Text = '推荐扩展（可选，手动安装）'
$secExt.Location = New-Object System.Drawing.Point(10, 426)
$secExt.Size = New-Object System.Drawing.Size(1110, 130)
$secExt.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$searchTab.Controls.Add($secExt)

$extIntro = New-Object System.Windows.Forms.Label
$extIntro.Text = "Brave Shields 本身就是原生级广告/追踪拦截器（与 uBlock Origin 采用相同规则源，且在内核引擎中运行，速度更轻快）。我们不会强制静默安装任何扩展——因为那会显示【由贵组织管理】横幅并锁定扩展。点击下方按钮将在 Brave 中直接打开安装页面，由您自主决定。" 
$extIntro.Location = New-Object System.Drawing.Point(15, 22)
$extIntro.Size = New-Object System.Drawing.Size(1080, 36)
$extIntro.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$extIntro.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$secExt.Controls.Add($extIntro)

$extWarn = New-Object System.Windows.Forms.Label
$extWarn.Text = '提示：在 Shields 之上叠加 uBlock Origin 属于双重拦截。会增加每个标签页的 CPU 开销，并可能导致网页排版异常。若安装 uBO，建议将 Shields 设为标准模式以减少规则冲突。' 
$extWarn.Location = New-Object System.Drawing.Point(15, 60)
$extWarn.Size = New-Object System.Drawing.Size(1080, 32)
$extWarn.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$extWarn.ForeColor = [System.Drawing.Color]::FromArgb(160, 70, 30)
$secExt.Controls.Add($extWarn)

$btnUboLite = New-Object System.Windows.Forms.Button
$btnUboLite.Text = '安装 uBlock Origin Lite (MV3)'
$btnUboLite.Size = New-Object System.Drawing.Size(220, 28)
$btnUboLite.Location = New-Object System.Drawing.Point(15, 95)
$btnUboLite.Add_Click({
    $exe = Test-BraveInstalled
    $url = 'https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh'
    if ($exe) { Start-Process $exe $url } else { Start-Process $url }
    Write-Log 'Opened uBlock Origin Lite install page.'
})
$secExt.Controls.Add($btnUboLite)

$btnShieldsSettings = New-Object System.Windows.Forms.Button
$btnShieldsSettings.Text = '打开 Brave Shields 防护设置'
$btnShieldsSettings.Size = New-Object System.Drawing.Size(200, 28)
$btnShieldsSettings.Location = New-Object System.Drawing.Point(245, 95)
$btnShieldsSettings.Add_Click({
    $exe = Test-BraveInstalled
    if ($exe) { Start-Process $exe 'brave://settings/shields' } else { Write-Log 'Brave not found.' 'WARN' }
})
$secExt.Controls.Add($btnShieldsSettings)

$btnBitwarden = New-Object System.Windows.Forms.Button
$btnBitwarden.Text = '安装 Bitwarden (密码管理器)'
$btnBitwarden.Size = New-Object System.Drawing.Size(240, 28)
$btnBitwarden.Location = New-Object System.Drawing.Point(455, 95)
$btnBitwarden.Add_Click({
    $exe = Test-BraveInstalled
    $url = 'https://chromewebstore.google.com/detail/bitwarden-password-manage/nngceckbapebfimnlniiiahkandclblb'
    if ($exe) { Start-Process $exe $url } else { Start-Process $url }
    Write-Log 'Opened Bitwarden install page.'
})
$secExt.Controls.Add($btnBitwarden)

$tabs.TabPages.Add($searchTab)

# ---- Helpers: write search-engine + startup overrides into one channel ------
function Resolve-Destination {
    param([string]$DropdownLabel, [string]$CustomUrl, [string]$SearchEngineHome)
    $code = $script:DestinationOptions[$DropdownLabel]
    switch ($code) {
        '__SKIP__'   { return $null }
        '__SEARCH__' { return $SearchEngineHome }
        '__CUSTOM__' { return $CustomUrl.Trim() }
        default      { return $code }
    }
}

function Apply-SearchEngineOverride {
    param([string]$Path)
    # Always clear first so toggling off truly removes them
    foreach ($n in @('DefaultSearchProviderEnabled','DefaultSearchProviderName','DefaultSearchProviderKeyword','DefaultSearchProviderSearchURL','DefaultSearchProviderSuggestURL')) {
        try { Remove-ItemProperty -Path $Path -Name $n -ErrorAction Stop } catch {}
    }
    if (-not $script:ChkSearchOverride.Checked) { return $false }

    $engineKey = $script:CmbSearchEngine.SelectedItem
    $eng = $script:SearchEngines[$engineKey]
    $url = $eng.URL
    $sug = $eng.Suggest
    $name = $engineKey
    $keyword = $eng.Keyword
    if ($eng.IsCustom) {
        $url = $script:TxtCustomSearchUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($url)) { Write-Log 'Search override skipped: custom URL is empty.' 'WARN'; return $false }
        if ($url -notmatch '\{searchTerms\}') { Write-Log 'Search override skipped: custom URL must contain {searchTerms}.' 'WARN'; return $false }
        $name = 'Custom Search'
    }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name 'DefaultSearchProviderEnabled'   -Value 1     -PropertyType DWord  -Force | Out-Null
    New-ItemProperty -Path $Path -Name 'DefaultSearchProviderName'      -Value $name -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $Path -Name 'DefaultSearchProviderKeyword'   -Value $keyword -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $Path -Name 'DefaultSearchProviderSearchURL' -Value $url  -PropertyType String -Force | Out-Null
    if ($sug) {
        New-ItemProperty -Path $Path -Name 'DefaultSearchProviderSuggestURL' -Value $sug -PropertyType String -Force | Out-Null
    }
    Write-Log "Search engine override -> $name" 'OK'
    return $true
}

function Apply-NtpOverride {
    param([string]$Path)
    # Clear first
    try { Remove-ItemProperty -Path $Path -Name 'NewTabPageLocation' -ErrorAction Stop } catch {}
    if (-not $script:ChkNtpOverride.Checked) { return $false }

    # Resolve destination
    $engineKey = $script:CmbSearchEngine.SelectedItem
    $engineHome = if ($script:SearchEngines[$engineKey].IsCustom) { '' } else { $script:SearchEngines[$engineKey].Home }
    $url = Resolve-Destination -DropdownLabel $script:CmbNtpDest.SelectedItem -CustomUrl $script:TxtNtpCustomUrl.Text -SearchEngineHome $engineHome
    if (-not $url) { Write-Log 'NTP override skipped: no resolvable URL.' 'WARN'; return $false }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name 'NewTabPageLocation' -Value $url -PropertyType String -Force | Out-Null
    Write-Log "New tab page override -> $url" 'OK'
    return $true
}

function Apply-StartupOverride {
    param([string]$Path)
    # Clear first
    try { Remove-ItemProperty -Path $Path -Name 'RestoreOnStartup' -ErrorAction Stop } catch {}
    try { Remove-Item -Path (Join-Path $Path 'RestoreOnStartupURLs') -Recurse -Force -ErrorAction Stop } catch {}
    if (-not $script:ChkStartupOverride.Checked) { return $false }

    $modeKey = $script:CmbStartupMode.SelectedItem
    $mode = $script:StartupModes[$modeKey]
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name 'RestoreOnStartup' -Value $mode.Code -PropertyType DWord -Force | Out-Null

    if ($mode.UsesURL) {
        $listPath = Join-Path $Path 'RestoreOnStartupURLs'
        New-Item -Path $listPath -Force | Out-Null
        $urls = if ($mode.FixedURL) { @($mode.FixedURL) }
                else { ($script:TxtStartupUrl.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        if ($urls.Count -eq 0) { Write-Log 'Startup override skipped: no URL provided.' 'WARN'; return $false }
        $i = 1
        foreach ($u in $urls) {
            New-ItemProperty -Path $listPath -Name "$i" -Value $u -PropertyType String -Force | Out-Null
            $i++
        }
        Write-Log "Startup override -> code $($mode.Code), URLs: $($urls -join ', ')" 'OK'
    } else {
        Write-Log "Startup override -> $modeKey (code $($mode.Code))" 'OK'
    }
    return $true
}

# ---- Utility buttons --------------------------------------------------------
$utilityPanel = New-Object System.Windows.Forms.Panel
$utilityPanel.Location = New-Object System.Drawing.Point(10, 676)
$utilityPanel.Size = New-Object System.Drawing.Size(1145, 40)
$utilityPanel.Anchor = 'Left, Right, Bottom'
$form.Controls.Add($utilityPanel)

# Export config to JSON
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = '导出配置'
$btnExport.Size = New-Object System.Drawing.Size(110, 30)
$btnExport.Location = New-Object System.Drawing.Point(420, 5)
$btnExport.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = 'JSON config (*.json)|*.json'
    $sfd.FileName = "brave-free-origin-config-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $sfd.InitialDirectory = Join-Path $env:USERPROFILE 'Documents\Brave-Free-Origin-Backups'
    if (-not (Test-Path $sfd.InitialDirectory)) { New-Item -ItemType Directory -Path $sfd.InitialDirectory | Out-Null }
    if ($sfd.ShowDialog() -ne 'OK') { return }

    $cfg = [ordered]@{
        version  = '1.11'
        exported = (Get-Date -Format 's')
        channel  = $script:TargetChannels
        profile  = $script:ActiveProfile
        policies = [ordered]@{}
        policyValues = [ordered]@{}
        tasks    = [ordered]@{}
        services = [ordered]@{}
        hosts    = [ordered]@{}
        search   = [ordered]@{
            enabled    = [bool]$script:ChkSearchOverride.Checked
            engine     = "$($script:CmbSearchEngine.SelectedItem)"
            customUrl  = "$($script:TxtCustomSearchUrl.Text)"
        }
        ntp = [ordered]@{
            enabled    = [bool]$script:ChkNtpOverride.Checked
            destination= "$($script:CmbNtpDest.SelectedItem)"
            customUrl  = "$($script:TxtNtpCustomUrl.Text)"
        }
        startup = [ordered]@{
            enabled    = [bool]$script:ChkStartupOverride.Checked
            mode       = "$($script:CmbStartupMode.SelectedItem)"
            urls       = "$($script:TxtStartupUrl.Text)"
        }
    }
    foreach ($cb in $script:CheckBoxes)        {
        $cfg.policies[$cb.Tag.Policy.Name] = [bool]$cb.Checked
        # Remember the picked value for choice policies (e.g. hardware accel).
        if ($cb.Tag.Policy.Choices) { $cfg.policyValues[$cb.Tag.Policy.Name] = $cb.Tag.Policy.ApplyValue }
    }
    foreach ($cb in $script:TaskCheckBoxes)    { $cfg.tasks[$cb.Tag.Name]            = [bool]$cb.Checked }
    foreach ($cb in $script:ServiceCheckBoxes) { $cfg.services[$cb.Tag.Name]         = [bool]$cb.Checked }
    foreach ($cb in $script:HostsCheckBoxes)   { $cfg.hosts[$cb.Tag.Name]            = [bool]$cb.Checked }

    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $sfd.FileName -Encoding UTF8
    Write-Log "Config exported: $($sfd.FileName)" 'OK'
})
$utilityPanel.Controls.Add($btnExport)

# Import config from JSON
$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = '导入配置'
$btnImport.Size = New-Object System.Drawing.Size(110, 30)
$btnImport.Location = New-Object System.Drawing.Point(535, 5)
$btnImport.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'JSON config (*.json)|*.json'
    $ofd.InitialDirectory = Join-Path $env:USERPROFILE 'Documents\Brave-Free-Origin-Backups'
    if ($ofd.ShowDialog() -ne 'OK') { return }
    try {
        $cfg = Get-Content $ofd.FileName -Raw | ConvertFrom-Json
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Bad JSON: $_", 'Import error', 'OK', 'Error') | Out-Null
        return
    }
    $script:SuppressSelectionEvents = $true
    if ($cfg.policies) {
        foreach ($cb in $script:CheckBoxes) {
            $name = $cb.Tag.Policy.Name
            if ($cfg.policies.PSObject.Properties.Name -contains $name) { $cb.Checked = [bool]$cfg.policies.$name }
        }
    }
    if ($cfg.policyValues) {
        # Restore the picked value for choice policies (e.g. hardware accel).
        foreach ($cb in $script:CheckBoxes) {
            $p = $cb.Tag.Policy
            if (-not $p.Choices) { continue }
            if ($cfg.policyValues.PSObject.Properties.Name -notcontains $p.Name) { continue }
            $wanted = "$($cfg.policyValues.$($p.Name))"
            $combo  = $script:PolicyCombos[$p.Name]
            foreach ($label in $p.Choices.Keys) {
                if ("$($p.Choices[$label])" -eq $wanted) {
                    if ($combo) { $combo.SelectedItem = $label } else { $p.ApplyValue = $p.Choices[$label] }
                    break
                }
            }
        }
    }
    if ($cfg.tasks) {
        foreach ($cb in $script:TaskCheckBoxes) {
            $name = $cb.Tag.Name
            if ($cfg.tasks.PSObject.Properties.Name -contains $name) { $cb.Checked = [bool]$cfg.tasks.$name }
        }
    }
    if ($cfg.services) {
        foreach ($cb in $script:ServiceCheckBoxes) {
            $name = $cb.Tag.Name
            if ($cfg.services.PSObject.Properties.Name -contains $name) { $cb.Checked = [bool]$cfg.services.$name }
        }
    }
    if ($cfg.hosts) {
        foreach ($cb in $script:HostsCheckBoxes) {
            $name = $cb.Tag.Name
            if ($cfg.hosts.PSObject.Properties.Name -contains $name) { $cb.Checked = [bool]$cfg.hosts.$name }
        }
    }
    if ($cfg.search) {
        $script:ChkSearchOverride.Checked = [bool]$cfg.search.enabled
        if ($cfg.search.engine -and $script:CmbSearchEngine.Items.Contains($cfg.search.engine)) {
            $script:CmbSearchEngine.SelectedItem = $cfg.search.engine
        }
        if ($cfg.search.customUrl) { $script:TxtCustomSearchUrl.Text = $cfg.search.customUrl }
    }
    if ($cfg.ntp) {
        $script:ChkNtpOverride.Checked = [bool]$cfg.ntp.enabled
        if ($cfg.ntp.destination -and $script:CmbNtpDest.Items.Contains($cfg.ntp.destination)) {
            $script:CmbNtpDest.SelectedItem = $cfg.ntp.destination
        }
        if ($cfg.ntp.customUrl) { $script:TxtNtpCustomUrl.Text = $cfg.ntp.customUrl }
    }
    if ($cfg.startup) {
        $script:ChkStartupOverride.Checked = [bool]$cfg.startup.enabled
        if ($cfg.startup.mode -and $script:CmbStartupMode.Items.Contains($cfg.startup.mode)) {
            $script:CmbStartupMode.SelectedItem = $cfg.startup.mode
        }
        if ($cfg.startup.urls) { $script:TxtStartupUrl.Text = $cfg.startup.urls }
    }
    $script:SuppressSelectionEvents = $false
    $script:ActiveProfile = if ($cfg.profile) { "$($cfg.profile)" } else { 'Custom' }
    Update-SelectionSummary
    Write-Log "Config imported from $($ofd.FileName) (version $($cfg.version))" 'OK'
    [System.Windows.Forms.MessageBox]::Show(
        "配置已成功加载至各勾选框。`r`n请点击【应用到 Brave】（以及按需在 Hosts 选项卡中点击应用）以提交生效。",
        '导入成功', 'OK', 'Information') | Out-Null
})
$utilityPanel.Controls.Add($btnImport)

# Verify - read registry, compare to UI selections
$btnVerify = New-Object System.Windows.Forms.Button
$btnVerify.Text = '校验策略'
$btnVerify.Size = New-Object System.Drawing.Size(80, 30)
$btnVerify.Location = New-Object System.Drawing.Point(650, 5)
$btnVerify.Add_Click({
    $report = New-Object System.Text.StringBuilder
    foreach ($channel in $script:TargetChannels) {
        $path = $script:Channels[$channel].Path
        [void]$report.AppendLine("=== $channel  ($path) ===")
        if (-not (Test-Path $path)) {
            [void]$report.AppendLine('  (no policy key exists - nothing applied)')
            [void]$report.AppendLine('')
            continue
        }
        $matchCount = 0; $missingCount = 0; $mismatchCount = 0; $tickedCount = 0
        $missingList = @(); $mismatchList = @()
        foreach ($cb in $script:CheckBoxes) {
            if (-not $cb.Checked) { continue }
            $tickedCount++
            $p = $cb.Tag.Policy
            try {
                $cur = (Get-ItemProperty -Path $path -Name $p.Name -ErrorAction Stop).$($p.Name)
                if ("$cur" -eq "$($p.ApplyValue)") { $matchCount++ }
                else { $mismatchCount++; $mismatchList += "$($p.Name): registry=$cur, expected=$($p.ApplyValue)" }
            } catch {
                $missingCount++; $missingList += $p.Name
            }
        }
        [void]$report.AppendLine("  Ticked in UI: $tickedCount")
        [void]$report.AppendLine("  Match in registry: $matchCount")
        [void]$report.AppendLine("  Missing (not in registry): $missingCount")
        [void]$report.AppendLine("  Mismatch (wrong value): $mismatchCount")
        if ($missingList) {
            [void]$report.AppendLine('  -- missing:')
            foreach ($n in $missingList) { [void]$report.AppendLine("     - $n") }
        }
        if ($mismatchList) {
            [void]$report.AppendLine('  -- mismatch:')
            foreach ($n in $mismatchList) { [void]$report.AppendLine("     - $n") }
        }
        [void]$report.AppendLine('')
    }

    # Hosts state
    $hostsCurrent = Get-HostsCurrentDomains
    [void]$report.AppendLine("=== Hosts blocklist ===")
    [void]$report.AppendLine("  Currently blocked domains: $($hostsCurrent.Count)")
    if ($hostsCurrent.Count -gt 0) {
        foreach ($d in $hostsCurrent) { [void]$report.AppendLine("     - $d") }
    }
    [void]$report.AppendLine('')

    # Search / NTP / Startup overrides
    [void]$report.AppendLine('=== Search & Startup overrides ===')
    foreach ($channel in $script:TargetChannels) {
        $path = $script:Channels[$channel].Path
        [void]$report.AppendLine("  [$channel]")
        if (-not (Test-Path $path)) { [void]$report.AppendLine('     (no policy key - nothing set)'); continue }
        try {
            $se = (Get-ItemProperty -Path $path -Name 'DefaultSearchProviderEnabled' -ErrorAction Stop).DefaultSearchProviderEnabled
            $name = (Get-ItemProperty -Path $path -Name 'DefaultSearchProviderName' -ErrorAction SilentlyContinue).DefaultSearchProviderName
            $url  = (Get-ItemProperty -Path $path -Name 'DefaultSearchProviderSearchURL' -ErrorAction SilentlyContinue).DefaultSearchProviderSearchURL
            if ($se -eq 1) { [void]$report.AppendLine("     Search engine forced: $name ($url)") }
            else           { [void]$report.AppendLine('     Search engine override: not set') }
        } catch { [void]$report.AppendLine('     Search engine override: not set') }
        try {
            $ntp = (Get-ItemProperty -Path $path -Name 'NewTabPageLocation' -ErrorAction Stop).NewTabPageLocation
            [void]$report.AppendLine("     New tab page forced: $ntp")
        } catch { [void]$report.AppendLine('     New tab page override: not set') }
        try {
            $rc = (Get-ItemProperty -Path $path -Name 'RestoreOnStartup' -ErrorAction Stop).RestoreOnStartup
            $listPath = Join-Path $path 'RestoreOnStartupURLs'
            $urls = @()
            if (Test-Path $listPath) {
                $props = Get-ItemProperty -Path $listPath
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -match '^\d+$') { $urls += $p.Value }
                }
            }
            $extra = if ($urls.Count -gt 0) { " URLs: $($urls -join ', ')" } else { '' }
            [void]$report.AppendLine("     Startup forced: code $rc$extra")
        } catch { [void]$report.AppendLine('     Startup override: not set') }
    }

    Show-TextReport -Title 'Verify - registry vs selections' -Text ($report.ToString()) -DefaultFileName "brave-free-origin-verify-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
})
$utilityPanel.Controls.Add($btnVerify)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = '读取当前系统状态'
$btnLoad.Size = New-Object System.Drawing.Size(145, 30)
$btnLoad.Location = New-Object System.Drawing.Point(0, 5)
$btnLoad.Add_Click({
    $script:SuppressSelectionEvents = $true
    # Read from the FIRST target channel (loading is single-source by design)
    $loadPath = $script:Channels[$script:TargetChannels[0]].Path
    $originalPath = $script:BravePolicyPath
    $script:BravePolicyPath = $loadPath
    foreach ($cb in $script:CheckBoxes) {
        $p = $cb.Tag.Policy
        $cur = Get-ExistingPolicy $p.Name
        if ($p.Choices) {
            # A choice policy counts as "on" whenever a value is present; point
            # the picker at whatever the registry actually holds.
            if ($null -ne $cur) {
                $combo = $script:PolicyCombos[$p.Name]
                foreach ($label in $p.Choices.Keys) {
                    if ("$($p.Choices[$label])" -eq "$cur") {
                        if ($combo) { $combo.SelectedItem = $label } else { $p.ApplyValue = $p.Choices[$label] }
                        break
                    }
                }
                $cb.Checked = $true
            } else {
                $cb.Checked = $false
            }
        } else {
            $cb.Checked = ($null -ne $cur -and "$cur" -eq "$($p.ApplyValue)")
        }
    }
    $script:BravePolicyPath = $originalPath
    foreach ($cb in $script:TaskCheckBoxes) {
        $t = $cb.Tag
        $task = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        $cb.Checked = ($task -and $task.State -eq 'Disabled')
    }
    foreach ($cb in $script:ServiceCheckBoxes) {
        $s = $cb.Tag
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        $cb.Checked = ($svc -and $svc.StartType -eq 'Disabled')
    }
    # Hosts state
    if ($script:HostsCheckBoxes) {
        $current = Get-HostsCurrentDomains
        foreach ($cb in $script:HostsCheckBoxes) {
            $blockDomains = $cb.Tag.Domains
            $allPresent = $true
            foreach ($d in $blockDomains) { if ($current -notcontains $d) { $allPresent = $false; break } }
            $cb.Checked = $allPresent
        }
    }
    # Search engine override state
    if ($script:ChkSearchOverride) {
        $sePath = $loadPath
        $seEnabled = $false
        try {
            $val = (Get-ItemProperty -Path $sePath -Name 'DefaultSearchProviderEnabled' -ErrorAction Stop).DefaultSearchProviderEnabled
            $seEnabled = ($val -eq 1)
        } catch { $seEnabled = $false }
        $script:ChkSearchOverride.Checked = $seEnabled
        if ($seEnabled) {
            try {
                $url = (Get-ItemProperty -Path $sePath -Name 'DefaultSearchProviderSearchURL' -ErrorAction Stop).DefaultSearchProviderSearchURL
                $matched = $false
                foreach ($key in $script:SearchEngines.Keys) {
                    if (-not $script:SearchEngines[$key].IsCustom -and $script:SearchEngines[$key].URL -eq $url) {
                        $script:CmbSearchEngine.SelectedItem = $key
                        $matched = $true; break
                    }
                }
                if (-not $matched) {
                    $script:CmbSearchEngine.SelectedItem = '自定义 (Custom)...'
                    $script:TxtCustomSearchUrl.Text = $url
                }
            } catch {}
        }
    }
    # NTP override state
    if ($script:ChkNtpOverride) {
        try {
            $ntpUrl = (Get-ItemProperty -Path $loadPath -Name 'NewTabPageLocation' -ErrorAction Stop).NewTabPageLocation
            $script:ChkNtpOverride.Checked = $true
            $matched = $false
            foreach ($k in $script:DestinationOptions.Keys) {
                if ($script:DestinationOptions[$k] -eq $ntpUrl) {
                    $script:CmbNtpDest.SelectedItem = $k; $matched = $true; break
                }
            }
            if (-not $matched) {
                $script:CmbNtpDest.SelectedItem = '自定义网址 (Custom URL)...'
                $script:TxtNtpCustomUrl.Text = $ntpUrl
            }
        } catch { $script:ChkNtpOverride.Checked = $false }
    }
    # Startup override state
    if ($script:ChkStartupOverride) {
        try {
            $code = (Get-ItemProperty -Path $loadPath -Name 'RestoreOnStartup' -ErrorAction Stop).RestoreOnStartup
            $script:ChkStartupOverride.Checked = $true
            foreach ($k in $script:StartupModes.Keys) {
                if ($script:StartupModes[$k].Code -eq $code) { $script:CmbStartupMode.SelectedItem = $k; break }
            }
            $listPath = Join-Path $loadPath 'RestoreOnStartupURLs'
            if (Test-Path $listPath) {
                $props = Get-ItemProperty -Path $listPath
                $urls = @()
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -match '^\d+$') { $urls += $p.Value }
                }
                if ($urls.Count -gt 0) { $script:TxtStartupUrl.Text = ($urls -join ', ') }
            }
        } catch { $script:ChkStartupOverride.Checked = $false }
    }
    $script:SuppressSelectionEvents = $false
    $script:ActiveProfile = 'CurrentState'
    Update-SelectionSummary
    Write-Log 'Loaded current system state.'
})
$utilityPanel.Controls.Add($btnLoad)

$btnOpenBrave = New-Object System.Windows.Forms.Button
$btnOpenBrave.Text = '打开 brave://policy'
$btnOpenBrave.Size = New-Object System.Drawing.Size(150, 30)
$btnOpenBrave.Location = New-Object System.Drawing.Point(155, 5)
$btnOpenBrave.Add_Click({
    $exe = Test-BraveInstalled
    if ($exe) { Start-Process $exe 'brave://policy' }
    else { [System.Windows.Forms.MessageBox]::Show('Brave not found on this machine.', 'Info') | Out-Null }
})
$utilityPanel.Controls.Add($btnOpenBrave)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = '关闭'
$btnClose.Size = New-Object System.Drawing.Size(95, 30)
$btnClose.Location = New-Object System.Drawing.Point(315, 5)
$btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $btnClose
$btnClose.Add_Click({ $form.Close() })
$utilityPanel.Controls.Add($btnClose)

$flowLabel = New-Object System.Windows.Forms.Label
$flowLabel.Text = '流程：选择模式 -> 微调策略 -> 预览变更 -> 应用到 Brave -> 重启浏览器 -> 校验策略'
$flowLabel.Location = New-Object System.Drawing.Point(740, 11)
$flowLabel.Size = New-Object System.Drawing.Size(400, 18)
$flowLabel.ForeColor = [System.Drawing.Color]::DimGray
$utilityPanel.Controls.Add($flowLabel)

# ---- Action buttons ---------------------------------------------------------
$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Location = New-Object System.Drawing.Point(10, 720)
$actionPanel.Size = New-Object System.Drawing.Size(1145, 44)
$actionPanel.Anchor = 'Left, Right, Bottom'
$form.Controls.Add($actionPanel)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = '应用前自动备份现有策略'
$chkBackup.Checked = $true
$chkBackup.Location = New-Object System.Drawing.Point(0, 12)
$chkBackup.Size = New-Object System.Drawing.Size(270, 20)
$actionPanel.Controls.Add($chkBackup)

$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text = '预览变更'
$btnPreview.Size = New-Object System.Drawing.Size(140, 34)
$btnPreview.Location = New-Object System.Drawing.Point(280, 4)
$btnPreview.Add_Click({
    Show-TextReport -Title 'Preview apply changes' -Text (New-ApplyPlanReport) -DefaultFileName "brave-free-origin-apply-preview-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
})
$actionPanel.Controls.Add($btnPreview)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = '应用到 Brave'
$btnApply.Size = New-Object System.Drawing.Size(150, 34)
$btnApply.Location = New-Object System.Drawing.Point(430, 4)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 63)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$btnApply.Add_Click({
    if ($chkBackup.Checked) { [void](Export-Backup) }

    $applied = 0
    $cleared = 0
    $originalPath = $script:BravePolicyPath
    foreach ($channel in $script:TargetChannels) {
        $script:BravePolicyPath = $script:Channels[$channel].Path
        Write-Log "--- Applying to channel: $channel ($($script:BravePolicyPath)) ---"
        foreach ($cb in $script:CheckBoxes) {
            $p = $cb.Tag.Policy
            if ($cb.Checked) {
                try {
                    Set-PolicyValue -Name $p.Name -Type $p.Type -Value $p.ApplyValue
                    Write-Log "[$channel] SET $($p.Name) = $($p.ApplyValue)" 'OK'
                    $applied++
                } catch {
                    Write-Log "[$channel] FAIL $($p.Name): $_" 'ERR'
                }
            } else {
                if (Remove-PolicyValue -Name $p.Name) {
                    Write-Log "[$channel] CLEARED $($p.Name)" 'OK'
                    $cleared++
                }
            }
        }

        # Search/NTP/Startup overrides run LAST so they always win over any
        # NewTabPageLocation/HomepageLocation/RestoreOnStartup ticks above.
        # Each helper clears its own keys first, so unticking + Apply truly removes them.
        if ($script:BravePolicyPath -and (Test-Path $script:BravePolicyPath)) {
            try { [void](Apply-SearchEngineOverride -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] Search override: $_" 'ERR' }
            try { [void](Apply-NtpOverride          -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] NTP override: $_" 'ERR' }
            try { [void](Apply-StartupOverride      -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] Startup override: $_" 'ERR' }
        } elseif ($script:ChkSearchOverride.Checked -or $script:ChkNtpOverride.Checked -or $script:ChkStartupOverride.Checked) {
            # No policy key yet but overrides are requested - create the key and run them
            New-Item -Path $script:BravePolicyPath -Force | Out-Null
            try { [void](Apply-SearchEngineOverride -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] Search override: $_" 'ERR' }
            try { [void](Apply-NtpOverride          -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] NTP override: $_" 'ERR' }
            try { [void](Apply-StartupOverride      -Path $script:BravePolicyPath) } catch { Write-Log "[$channel] Startup override: $_" 'ERR' }
        }
    }
    $script:BravePolicyPath = $originalPath

    foreach ($cb in $script:TaskCheckBoxes) {
        $t = $cb.Tag
        try {
            if ($cb.Checked) {
                Disable-ScheduledTask -TaskName $t.Name -ErrorAction Stop | Out-Null
                Write-Log "DISABLED task $($t.Name)" 'OK'
            } else {
                $existing = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
                if ($existing -and $existing.State -eq 'Disabled') {
                    Enable-ScheduledTask -TaskName $t.Name -ErrorAction Stop | Out-Null
                    Write-Log "ENABLED task $($t.Name)" 'OK'
                }
            }
        } catch {
            Write-Log "Task $($t.Name): $_" 'WARN'
        }
    }

    foreach ($cb in $script:ServiceCheckBoxes) {
        $s = $cb.Tag
        try {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Log "Service $($s.Name) not present - skipped." 'INFO'
                continue
            }
            if ($cb.Checked) {
                if ($svc.Status -eq 'Running') { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $s.Name -StartupType Disabled -ErrorAction Stop
                Write-Log "DISABLED service $($s.Name)" 'OK'
            } else {
                if ($svc.StartType -eq 'Disabled') {
                    Set-Service -Name $s.Name -StartupType Manual -ErrorAction Stop
                    Write-Log "RESET service $($s.Name) to Manual" 'OK'
                }
            }
        } catch {
            Write-Log "Service $($s.Name): $_" 'WARN'
        }
    }

    Update-SelectionSummary
    Write-Log "Done. Applied $applied policies, cleared $cleared. Restart Brave to take effect." 'DONE'
    $activeModeLabel = if ($script:ProfileDisplayNames.ContainsKey($script:ActiveProfile)) { $script:ProfileDisplayNames[$script:ActiveProfile] } else { $script:ActiveProfile }
    [System.Windows.Forms.MessageBox]::Show(
        "当前模式: $activeModeLabel`r`n已应用 $applied 条策略，已清除 $cleared 条。`r`n`r`n请完全重启 Brave 浏览器以使改动生效。`r`n可在浏览器中访问 brave://policy 检验生效情况。",
        'Brave Free Origin',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})
$actionPanel.Controls.Add($btnApply)

$btnRemoveAll = New-Object System.Windows.Forms.Button
$btnRemoveAll.Text = '完全还原 / 恢复默认'
$btnRemoveAll.Size = New-Object System.Drawing.Size(170, 34)
$btnRemoveAll.Location = New-Object System.Drawing.Point(590, 4)
$btnRemoveAll.BackColor = [System.Drawing.Color]::FromArgb(150, 60, 60)
$btnRemoveAll.ForeColor = [System.Drawing.Color]::White
$btnRemoveAll.Add_Click({
    $targets = $script:TargetChannels -join ', '
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "这将为以下版本频道恢复官方默认状态: $targets`r`n`r`n操作将删除 Brave 策略注册表项、清除 Brave-Free-Origin hosts 屏蔽块、重新启用已知的 Brave 更新任务，并将已禁用的 Brave 更新服务重置为手动启动。`r`n`r`n是否继续？",
        '完全还原 / 恢复默认',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    Invoke-FullRestore -Backup $chkBackup.Checked
    [System.Windows.Forms.MessageBox]::Show('完全还原已完成。请重启 Brave 浏览器以恢复默认状态。', 'Brave Free Origin', 'OK', 'Information') | Out-Null
})
$actionPanel.Controls.Add($btnRemoveAll)

# ---- Log box ----------------------------------------------------------------
$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(10, 770)
$script:LogBox.Size = New-Object System.Drawing.Size(1145, 90)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.ReadOnly = $true
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
$script:LogBox.ForeColor = [System.Drawing.Color]::LightGreen
$script:LogBox.Anchor = 'Left, Right, Bottom'
$form.Controls.Add($script:LogBox)

Update-SelectionSummary

# ---- Form Closing & Cleanup ------------------------------------------------
$form.Add_FormClosing({
    if ($script:ScriptletScanTimer) { $script:ScriptletScanTimer.Stop() }
    if ($script:ScriptletRenderTimer) { $script:ScriptletRenderTimer.Stop() }
    if ($script:ScriptletFilterTimer) { $script:ScriptletFilterTimer.Stop() }
})

# ---- Startup ---------------------------------------------------------------
$form.Add_Shown({
    Write-Log '已获得管理员权限运行 - 正常。'
    Write-Log "Brave 版本: $braveVer"
    Write-Log '正在读取当前系统策略状态...'
    $btnLoad.PerformClick()
})

[void]$form.ShowDialog()
$form.Dispose()
[System.Windows.Forms.Application]::Exit()
exit 0
