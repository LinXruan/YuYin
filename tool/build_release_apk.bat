@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem ========================================================
rem YuYin Release APK Build Pipeline
rem Target options:
rem   build_release_apk.bat           [Default: build both v8a and Universal]
rem   build_release_apk.bat all       [Build both v8a and Universal]
rem   build_release_apk.bat v8a       [Build arm64-v8a lightweight]
rem   build_release_apk.bat universal [Build all-arch universal]
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

if not exist "android\key.properties" (
  echo [错误] 未找到 android\key.properties，无法进行 release 签名。
  echo        请先配置 release 私钥后再编译。
  popd
  exit /b 1
)

set "APP_VER=1.0.0"
for /f "tokens=2 delims=: " %%a in ('findstr /r "^version:" pubspec.yaml') do (
  for /f "tokens=1 delims=+" %%b in ("%%a") do set "APP_VER=%%b"
)

set "TARGET=%~1"
if not defined TARGET set "TARGET=all"

set "OUT_DIR=build\app\outputs\flutter-apk"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo ========================================================
echo   余音 YuYin Release 构建流水线 - 版本 v%APP_VER%
echo ========================================================

if /i "%TARGET%"=="all" goto :BUILD_V8A
if /i "%TARGET%"=="v8a" goto :BUILD_V8A
if /i "%TARGET%"=="arm64" goto :BUILD_V8A
goto :CHECK_UNIVERSAL

:BUILD_V8A
echo.
echo [1/2] 正在编译 v8a [arm64-v8a] 极速版...
call flutter build apk --release --target-platform android-arm64
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo [失败] v8a 版本编译失败，退出码 %RC%。
  popd
  exit /b %RC%
)

set "RAW_APK=build\app\outputs\apk\release\app-release.apk"
if not exist "%RAW_APK%" set "RAW_APK=%OUT_DIR%\app-release.apk"
set "FINAL_V8A=%OUT_DIR%\YuYin_%APP_VER%_v8a.apk"
if exist "%RAW_APK%" (
  copy /y "%RAW_APK%" "%FINAL_V8A%" >nul
  for %%i in ("%FINAL_V8A%") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo [完成] v8a 版生成成功: %%~nxi [!SIZE_MB! MB, %%~zi 字节]
  )
) else (
  echo [警告] 未找到生成的 v8a APK 产物。
)

if /i "%TARGET%"=="v8a" goto :DONE
if /i "%TARGET%"=="arm64" goto :DONE

:CHECK_UNIVERSAL
if /i "%TARGET%"=="all" goto :BUILD_UNIV
if /i "%TARGET%"=="universal" goto :BUILD_UNIV
echo [错误] 未知目标: %TARGET% [支持 all, v8a, universal]
popd
exit /b 1

:BUILD_UNIV
echo.
echo [2/2] 正在编译 Universal [全架构] 通用版...
call flutter build apk --release
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo [失败] Universal 版本编译失败，退出码 %RC%。
  popd
  exit /b %RC%
)

set "RAW_APK=build\app\outputs\apk\release\app-release.apk"
if not exist "%RAW_APK%" set "RAW_APK=%OUT_DIR%\app-release.apk"
set "FINAL_UNIV=%OUT_DIR%\YuYin_%APP_VER%_Universal.apk"
if exist "%RAW_APK%" (
  copy /y "%RAW_APK%" "%FINAL_UNIV%" >nul
  for %%i in ("%FINAL_UNIV%") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo [完成] Universal 版生成成功: %%~nxi [!SIZE_MB! MB, %%~zi 字节]
  )
) else (
  echo [警告] 未找到生成的 Universal APK 产物。
)

:DONE
rem ========================================================
rem 自动清理：清理历史旧版本的 Release APK 与测试编译快照
rem ========================================================
set "CLEAN_COUNT=0"
for /f "delims=" %%f in ('dir /b "%OUT_DIR%\YuYin_*_v8a.apk" 2^>nul') do (
  if not "%%~nxf"=="YuYin_%APP_VER%_v8a.apk" (
    del /f /q "%OUT_DIR%\%%~nxf" >nul 2>nul
    set /a "CLEAN_COUNT+=1"
  )
)
for /f "delims=" %%f in ('dir /b "%OUT_DIR%\YuYin_*_Universal.apk" 2^>nul') do (
  if not "%%~nxf"=="YuYin_%APP_VER%_Universal.apk" (
    del /f /q "%OUT_DIR%\%%~nxf" >nul 2>nul
    set /a "CLEAN_COUNT+=1"
  )
)
if !CLEAN_COUNT! GTR 0 (
  echo.
  echo [自动清理] 已清理 !CLEAN_COUNT! 个历史旧版本 Release APK
)

if exist "build\test_cache" (
  rmdir /s /q "build\test_cache" >nul 2>nul
  echo [自动清理] 已清理 build\test_cache 单元测试编译快照
)

echo.
echo ========================================================
echo   构建完成！产物列表 [目录: %OUT_DIR%\]:
if exist "%OUT_DIR%\YuYin_%APP_VER%_v8a.apk" (
  for %%i in ("%OUT_DIR%\YuYin_%APP_VER%_v8a.apk") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo   - [v8a]       %%~nxi [!SIZE_MB! MB]
  )
)
if exist "%OUT_DIR%\YuYin_%APP_VER%_Universal.apk" (
  for %%i in ("%OUT_DIR%\YuYin_%APP_VER%_Universal.apk") do (
    set /a "SIZE_MB=%%~zi / 1048576"
    echo   - [Universal] %%~nxi [!SIZE_MB! MB]
  )
)
echo ========================================================
popd
exit /b 0
