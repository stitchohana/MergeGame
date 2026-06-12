@echo off
title MergeGame Server
cd /d "%~dp0server"
echo ========================================
echo   MergeGame Server
echo   Game:    http://localhost:3000
echo   Cult:    http://localhost:3001
echo ========================================
echo.

:: Start cultivation server in background
start "MergeGame Cultivation" /MIN cmd /c "npx tsx src/cultivation_index.ts"

:: Start game server in foreground
npx tsx src/index.ts
