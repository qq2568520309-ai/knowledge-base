@echo off
chcp 65001 >nul
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo [1/2] 首次运行：创建虚拟环境并安装依赖，大约 1-2 分钟...
  python -m venv .venv
  if errorlevel 1 goto :err
  ".venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check -r requirements.txt
  if errorlevel 1 goto :err
)

echo [2/2] 启动本地预览，按 Ctrl+C 停止
echo       地址见下面这行输出（通常为 http://127.0.0.1:8000/knowledge-base/）
".venv\Scripts\python.exe" -m mkdocs serve -a 127.0.0.1:8000
goto :eof

:err
echo.
echo 安装失败：请确认已安装 Python 3.9+ 并加入 PATH，网络可访问 PyPI。
echo 国内网络可先执行：pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
pause
