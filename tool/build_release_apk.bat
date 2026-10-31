@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem 编译 release 版 APK（包名 com.release.yuyin，独立私钥签名）
rem 输出：build\app\outputs\apk\release\app-release.apk
rem 用法：双击运行，或在任意目录调用本脚本

rem 切换到项目根目录（脚本位于 <项目>\tool\ 下）
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

rem release 必须依赖 android/key.properties 与私钥文件，缺失时无法签名
if not exist "android\key.properties" (
  echo [错误] 未找到 android\key.properties，无法进行 release 签名。
  echo        请先配置 release 私钥后再编译。
  popd
  exit /b 1
)

echo 正在编译 release 版 APK：flutter build apk --release
call flutter build apk --release
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo [失败] 编译失败，退出码 %RC%。可运行 flutter doctor -v 检查环境。
  popd
  exit /b %RC%
)

rem 兼容 apk 与 flutter-apk 两种输出目录
set "APK=build\app\outputs\apk\release\app-release.apk"
if not exist "%APK%" set "APK=build\app\outputs\flutter-apk\app-release.apk"
if exist "%APK%" (
  for %%i in ("%APK%") do echo [完成] %%~fi  ^(%%~zi 字节，%%~ti^)
) else (
  echo [警告] 编译成功，但未找到 app-release.apk，请检查构建输出。
)
popd
exit /b 0
