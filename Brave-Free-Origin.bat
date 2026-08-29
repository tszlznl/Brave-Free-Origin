@echo off
REM -----------------------------------------------------------------------
REM  Brave Free Origin - Windows 启动器 (中文版)
REM  双击运行此文件。它采用单次 ExecutionPolicy Bypass 执行策略绕过，
REM  用户无需手动修改系统全局 PowerShell 策略。
REM  PowerShell 脚本将自动处理 UAC 管理员提权并打开图形配置界面。
REM -----------------------------------------------------------------------
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "SCRIPT=%~dp0Brave-Free-Origin.ps1"

if not exist "%SCRIPT%" (
    echo 【错误】在启动器同级目录下未找到 Brave-Free-Origin.ps1 文件。
    echo.
    echo 请确保已将压缩包中的所有文件完整解压后再运行，不要直接在压缩包内打开。
    pause
    exit /b 1
)

echo 正在启动 Brave Free Origin (中文版)...
echo 如果弹出 Windows 用户账户控制 (UAC) 权限提示，请点击“是”。
echo 如果弹出 SmartScreen 拦截，请点击“更多信息” -^> “仍要运行”。
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

if errorlevel 1 (
    echo.
    echo 启动器返回了非零退出代码。
    echo 请尝试右键点击此 BAT 文件，选择“以管理员身份运行”。
    pause
)

endlocal
