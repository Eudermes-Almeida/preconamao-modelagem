@echo off
rem Duplo clique para instalar. Para iniciar sem ninguem logado: botao direito, "Executar como administrador".
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar.ps1" %*
pause
