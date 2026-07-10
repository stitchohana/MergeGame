@echo off
title MergeGame - Install Dependencies
cd /d "%~dp0server"
echo ========================================
echo   Installing MergeGame Server Dependencies
echo ========================================
echo.
call npm install
echo.
if %ERRORLEVEL% equ 0 (
    echo Dependencies installed successfully.
) else (
    echo Failed to install dependencies. Check the output above.
)
pause
