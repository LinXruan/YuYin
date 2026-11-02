@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem ========================================================
rem YuYin Debug APK Build Pipeline
rem Output: build\app\outputs\flutter-apk\YuYin_<version>_debug.apk
rem ========================================================

pushd "%~dp0.." || (
  echo [错误] 无法进入项目根目录。
  exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
  echo [错误] 未找到 flutter 命令，请确认 Flutter SDK 已加入 PATH。
  popd
  exit /b 1
)

set "APP_VER=1.0.0"
for /f "tokens=2 delims=: " %%a in ('findstr /r "^version:" pubspec.yaml') do (
  for /f "tokens=1 delims=+" %%b in ("%%a") do set "APP_VER=%%b"
)

echo ========================================================
echo   余音 YuYin Debug 构建流水线 - 版本 v%APP_VER%
echo ========================================================
echo.
echo 正在编译 Debug 版 APK: flutter build apk --debug
call flutter build apk --debug
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo [失败] 编译失败，退出码 %RC%。
  popd
  exit /b %RC%
)

set "OUT_DIR=build\app\outputs\flutter-apk"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
set "RAW_APK=build\app\outputs\apk\debug\app-debug.apk"
if not exist "%RAW_APK%" set "RAW_APK=%OUT_DIR%\app-debug.apk"

set "FINAL_DEBUG=%OUT_DIR%\YuYin_%APP_VER%_debug.apk"
if exist "%RAW_APK%" (
  copy /y "%RAW_APK%" "%FINAL_DEBUG%" >nul
  for %%i in ("%FINAL_DEBUG%") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo [完成] Debug 版生成成功: %%~nxi [!SIZE_MB! MB, %%~zi 字节]
  )
) else (
  echo [警告] 编译成功，但未找到生成的 app-debug.apk。
)

rem ========================================================
rem 自动清理：清理历史旧版本的 Debug APK 与测试编译快照
rem ========================================================
set "CLEAN_COUNT=0"
for /f "delims=" %%f in ('dir /b "%OUT_DIR%\YuYin_*_debug.apk" 2^>nul') do (
  if not "%%~nxf"=="YuYin_%APP_VER%_debug.apk" (
    del /f /q "%OUT_DIR%\%%~nxf" >nul 2>nul
    set /a "CLEAN_COUNT+=1"
  )
)
if !CLEAN_COUNT! GTR 0 (
  echo [自动清理] 已清理 !CLEAN_COUNT! 个历史旧版本 Debug APK
)

if exist "build\test_cache" (
  rmdir /s /q "build\test_cache" >nul 2>nul
  echo [自动清理] 已清理 build\test_cache 单元测试编译快照
)

echo.
echo ========================================================
echo   构建完成！产物列表 [目录: %OUT_DIR%\]:
if exist "%FINAL_DEBUG%" (
  for %%i in ("%FINAL_DEBUG%") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo   - [debug]     %%~nxi [!SIZE_MB! MB]
  )
)
echo ========================================================
popd
exit /b 0
