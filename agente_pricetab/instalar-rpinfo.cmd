@echo off
rem Duplo clique para instalar o agente RPInfo. Para iniciar sem ninguem logado: botao direito, "Executar como administrador".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-rpinfo.ps1"
pause
