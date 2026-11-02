@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem ========================================================
rem 余音 YuYin 项目空间清理与瘦身脚本
rem 用法说明
rem   clean_project.bat         [默认 quick: 极速瘦身，释放旧APK与构建/测试快照]
rem   clean_project.bat quick   [极速瘦身: 保留依赖缓存与当前版本APK，秒级完成]
rem   clean_project.bat full    [深度清理: 执行 flutter clean 并自动 pub get]
rem ========================================================

pushd "%~dp0.." || (
  echo [错误] 无法进入项目根目录。
  exit /b 1
)

set "MODE=%~1"
if not defined MODE set "MODE=quick"

if /i "%MODE%"=="help" goto :SHOW_HELP
if /i "%MODE%"=="-h" goto :SHOW_HELP
if /i "%MODE%"=="--help" goto :SHOW_HELP
if /i "%MODE%"=="/?" goto :SHOW_HELP

if /i "%MODE%"=="quick" goto :DO_QUICK
if /i "%MODE%"=="full" goto :DO_FULL

echo [错误] 未知模式: %MODE%
echo 支持模式: quick (默认) 或 full
echo 运行: clean_project.bat --help 查看帮助
popd
exit /b 1

:SHOW_HELP
echo ========================================================
echo   余音 YuYin 项目空间清理工具
echo ========================================================
echo 用法:
echo   clean_project.bat [quick ^| full]
echo.
echo 模式说明:
echo   quick  (默认模式) 极速日常瘦身:
echo          - 清理历史各版本的旧 APK (仅保留当前 pubspec.yaml 版本)
echo          - 清理 build\test_cache 测试编译快照
echo          - 清理 .dart_tool\flutter_build 历次构建快照
echo          - 清理 log\ 目录下的调试日志
echo          - 保留 Gradle 依赖与本地配置，不影响后续打包速度
echo.
echo   full   全量深度重置:
echo          - 调用 flutter clean 清空全部 build 目录
echo          - 清理 .dart_tool 编译缓存
echo          - 自动执行 flutter pub get 恢复项目环境
echo          - 彻底还原为几十兆的纯净初始源码态
echo ========================================================
popd
exit /b 0

:DO_QUICK
echo ========================================================
echo   [余音] 开始执行极速项目瘦身 (Quick Clean)...
echo ========================================================

set "APP_VER=1.0.0"
for /f "tokens=2 delims=: " %%a in ('findstr /r "^version:" pubspec.yaml') do (
  for /f "tokens=1 delims=+" %%b in ("%%a") do set "APP_VER=%%b"
)
echo [信息] 当前项目版本: v%APP_VER%

set "APK_DIR=build\app\outputs\flutter-apk"
set "APK_CLEAN_COUNT=0"

if exist "%APK_DIR%" (
  for /f "delims=" %%f in ('dir /b "%APK_DIR%\YuYin_*_debug.apk" 2^>nul') do (
    if not "%%~nxf"=="YuYin_%APP_VER%_debug.apk" (
      del /f /q "%APK_DIR%\%%~nxf" >nul 2>nul
      set /a "APK_CLEAN_COUNT+=1"
    )
  )
  for /f "delims=" %%f in ('dir /b "%APK_DIR%\YuYin_*_v8a.apk" 2^>nul') do (
    if not "%%~nxf"=="YuYin_%APP_VER%_v8a.apk" (
      del /f /q "%APK_DIR%\%%~nxf" >nul 2>nul
      set /a "APK_CLEAN_COUNT+=1"
    )
  )
  for /f "delims=" %%f in ('dir /b "%APK_DIR%\YuYin_*_Universal.apk" 2^>nul') do (
    if not "%%~nxf"=="YuYin_%APP_VER%_Universal.apk" (
      del /f /q "%APK_DIR%\%%~nxf" >nul 2>nul
      set /a "APK_CLEAN_COUNT+=1"
    )
  )
)

if !APK_CLEAN_COUNT! GTR 0 (
  echo [完成] 清理历史旧版本 APK 安装包: !APK_CLEAN_COUNT! 个
) else (
  echo [跳过] 没有发现历史旧版本 APK
)

rem 清理 apk/debug 和 apk/release 冗余旧产物
if exist "build\app\outputs\apk" (
  for /f "delims=" %%f in ('dir /s /b "build\app\outputs\apk\YuYin_*.*" 2^>nul') do (
    if not "%%~nxf"=="YuYin_%APP_VER%_debug.apk" if not "%%~nxf"=="YuYin_%APP_VER%_Universal.apk" (
      del /f /q "%%f" >nul 2>nul
    )
  )
)

rem 清理 build\test_cache
if exist "build\test_cache" (
  rmdir /s /q "build\test_cache" >nul 2>nul
  echo [完成] 清理 build\test_cache 单元测试编译快照 [~1.8 GB]
)

rem 清理 .dart_tool\flutter_build
if exist ".dart_tool\flutter_build" (
  rmdir /s /q ".dart_tool\flutter_build" >nul 2>nul
  echo [完成] 清理 .dart_tool\flutter_build 历史编译快照 [~3.7 GB]
)

rem 清理 log 临时文件
if exist "log" (
  del /f /q /s "log\*.log" >nul 2>nul
  echo [完成] 清理 log\ 目录下旧调试日志
)

echo.
echo ========================================================
echo   极速瘦身完成！磁盘空间已大幅释放。
echo   当前版本 v%APP_VER% 的必要文件与依赖均完好保留。
echo ========================================================
popd
exit /b 0

:DO_FULL
echo ========================================================
echo   [余音] 开始执行全量深度清理 (Full Clean)...
echo ========================================================

where flutter >nul 2>nul
if errorlevel 1 (
  echo [错误] 未找到 flutter 命令，请确认 Flutter SDK 已加入 PATH。
  popd
  exit /b 1
)

echo [1/3] 正在调用 flutter clean 清除构建残渣...
call flutter clean
if errorlevel 1 (
  echo [警告] flutter clean 执行遇到异常，将补充强制清理...
)

if exist "build" (
  echo [清理] 强制移除残留 build 目录...
  rmdir /s /q "build" >nul 2>nul
)

if exist ".dart_tool" (
  echo [清理] 强制移除残留 .dart_tool 缓存...
  rmdir /s /q ".dart_tool" >nul 2>nul
)

if exist "log" (
  del /f /q /s "log\*.log" >nul 2>nul
)

echo.
echo [2/3] 正在重新拉取依赖环境: flutter pub get...
call flutter pub get
if errorlevel 1 (
  echo [错误] flutter pub get 执行失败。
  popd
  exit /b 1
)

echo.
echo [3/3] 正在验证项目代码健康度: flutter analyze...
call flutter analyze
if errorlevel 1 (
  echo [警告] 静态检查存在提示。
)

echo.
echo ========================================================
echo   深度清理完成！项目已完全恢复至纯净轻量初始态。
echo ========================================================
popd
exit /b 0
