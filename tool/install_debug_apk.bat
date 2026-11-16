@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem Install debug APK to a real device (USB first, wireless fallback).
rem Usage: double-click, or pass a serial: install_debug_apk.bat serial

call "%~dp0_select_device.bat" "%~1"
if errorlevel 1 exit /b 1

set "KIND=有线"
if "%DEVICE_KIND%"=="wifi" set "KIND=无线"

rem Prefer apk/ output, fall back to flutter-apk/.
set "APK=%~dp0..\build\app\outputs\apk\debug\app-debug.apk"
if not exist "%APK%" set "APK=%~dp0..\build\app\outputs\flutter-apk\app-debug.apk"
if not exist "%APK%" (
  echo [错误] 未找到 debug APK，请先执行 tool\build_debug_apk.bat
  exit /b 1
)
for %%i in ("%APK%") do set "APK=%%~fi"

for %%i in ("%APK%") do echo 正在安装 %%~nxi  ^(%%~zi 字节^)  到%KIND%设备 %SERIAL%
"%ADB%" -s "%SERIAL%" install -r "%APK%"
if errorlevel 1 (
  echo [失败] 安装失败，请检查设备连接状态。
  exit /b 1
)
echo [完成] debug 版已安装到 %SERIAL%。
exit /b 0