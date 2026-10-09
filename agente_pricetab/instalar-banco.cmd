@echo off
rem Duplo clique para instalar o agente do conector de banco. Para iniciar sem ninguem logado: botao direito, "Executar como administrador".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-banco.ps1"
pause
