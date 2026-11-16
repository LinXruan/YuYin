@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem Install release APK to a real device (USB first, wireless fallback).
rem Usage: double-click, or pass a serial: install_release_apk.bat serial

call "%~dp0_select_device.bat" "%~1"
if errorlevel 1 exit /b 1

set "KIND=有线"
if "%DEVICE_KIND%"=="wifi" set "KIND=无线"

rem Prefer v8a, then Universal, then the original app-release.apk.
set "APK="
for /f "delims=" %%i in ('dir /b /s "%~dp0..\build\app\outputs\flutter-apk\YuYin_*_v8a.apk" 2^>nul') do set "APK=%%i"
if not defined APK (
  for /f "delims=" %%i in ('dir /b /s "%~dp0..\build\app\outputs\flutter-apk\YuYin_*_Universal.apk" 2^>nul') do set "APK=%%i"
)
if not defined APK (
  if exist "%~dp0..\build\app\outputs\flutter-apk\app-release.apk" set "APK=%~dp0..\build\app\outputs\flutter-apk\app-release.apk"
)
if not defined APK (
  if exist "%~dp0..\build\app\outputs\apk\release\app-release.apk" set "APK=%~dp0..\build\app\outputs\apk\release\app-release.apk"
)
if not defined APK (
  echo [错误] 未找到 release APK，请先执行 tool\build_release_apk.bat
  exit /b 1
)

for %%i in ("%APK%") do (
  set "APK=%%~fi"
  set /a "SIZE_MB=%%~zi / 1048576"
  set "FILE_NAME=%%~nxi"
)

echo 目标设备：%SERIAL% ^(%KIND%^)
echo 正在安装 %FILE_NAME% (!SIZE_MB! MB)...
"%ADB%" -s "%SERIAL%" install -r "%APK%"
if errorlevel 1 (
  echo [失败] 安装失败，请检查设备连接状态。
  exit /b 1
)
echo [成功] 安装完成。
exit /b 0