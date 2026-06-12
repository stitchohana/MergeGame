@echo off
cd /d "%~dp0server"
echo ========================================
echo   MergeGame Server
echo ========================================
echo.
call npx tsx src/index.ts
pause
