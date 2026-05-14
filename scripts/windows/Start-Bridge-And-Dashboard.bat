@echo off
chcp 65001 >nul
title V-Teeth Bridge + Dashboard
cd /d "%~dp0..\..\"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_bridge_and_dashboard.ps1"
set ERR=%ERRORLEVEL%
if %ERR% neq 0 pause
exit /b %ERR%
