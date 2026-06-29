@echo off
title MergeGame Server
cd /d "%~dp0server"
echo ========================================
echo   MergeGame Server
echo   Game:    http://localhost:3000
echo ========================================
echo.

:: Start game server
npx tsx src/index.ts
