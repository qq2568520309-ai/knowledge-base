# 本地预览一键启动（PowerShell）
# 用法：右键 → 使用 PowerShell 运行，或在终端执行 .\启动预览.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (Test-Path '.venv\Scripts\python.exe') {
    $python = '.venv\Scripts\python.exe'
} else {
    Write-Host '[1/2] 首次运行：创建虚拟环境并安装依赖...' -ForegroundColor Cyan
    python -m venv .venv
    $python = '.venv\Scripts\python.exe'
    & $python -m pip install -q --disable-pip-version-check -r requirements.txt
}

Write-Host '[2/2] 启动本地预览，Ctrl+C 停止' -ForegroundColor Cyan
& $python -m mkdocs serve -a 127.0.0.1:8000
