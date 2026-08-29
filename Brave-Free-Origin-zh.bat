@echo off
REM ============================================================================
REM  Brave Free Origin - 中文启动器
REM  Brave Free Origin 是一个 Windows GUI 工具，用来通过企业策略精简 Brave 浏览器
REM ============================================================================

REM 检查 PowerShell 是否可用
where powershell >nul 2>nul
if errorlevel 1 (
    echo 错误: 未找到 PowerShell。
    echo 请确保已安装 PowerShell 5.0 或更新版本。
    pause
    exit /b 1
)

REM 用绕过执行策略的方式运行中文脚本
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Brave-Free-Origin.zh.ps1"

if errorlevel 1 (
    echo 脚本执行失败。
    pause
)
