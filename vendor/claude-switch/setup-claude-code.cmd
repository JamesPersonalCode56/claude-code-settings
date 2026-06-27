@echo off
REM Launcher: cai Claude Code + dien key tu .env (cung thu muc).
REM Chay: setup-claude-code.cmd        (them  -Test  de xac minh key bang 1 lenh API)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-claude-code.ps1" %*
echo.
pause
