@echo off
chcp 65001 >nul
setlocal

rem ========================================================
rem YuYin Agent Debug Bridge CLI
rem Usage:
rem   agent_cmd.bat setup
rem   agent_cmd.bat status
rem   agent_cmd.bat display
rem   agent_cmd.bat parse "<url_or_text>"
rem   agent_cmd.bat parse-works "<url_or_text>"
rem   agent_cmd.bat save-works "<url_or_text>"
rem   agent_cmd.bat save-home "<home_url>"
rem   agent_cmd.bat download [all|0,1]
rem   agent_cmd.bat logs
rem   agent_cmd.bat clear-logs
rem   agent_cmd.bat history [query]
rem   agent_cmd.bat history-scan "<id>"
rem   agent_cmd.bat clear-history
rem   agent_cmd.bat thumbnails
rem   agent_cmd.bat clear-thumbnails
rem   agent_cmd.bat preload-thumbnails
rem   agent_cmd.bat verify-covers
rem   agent_cmd.bat verify-titles
rem   agent_cmd.bat parse-profile "<url>"
rem   agent_cmd.bat verify-profile
rem   agent_cmd.bat cancel
rem ========================================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent_bridge.ps1" %*
exit /b %errorlevel%
