@echo off
rem Sai da pasta do agente: o desinstalador a apaga ao terminar (a pausa final fica no .ps1).
cd /d "%TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstalar.ps1"
