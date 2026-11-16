@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem Manual wireless ADB reconnect (reuse a connected device first).
rem Usage: tool\wifi_adb.bat [--list] [--serial ip:port]

set "PY=D:\Install\anaconda3\envs\deepseek\python.exe"
if not exist "%PY%" set "PY=python"

"%PY%" "%~dp0adb_wifi.py" %*
if errorlevel 1 (
  echo.
  pause
)
exit /b %errorlevel%
