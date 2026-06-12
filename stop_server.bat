@echo off
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":3000" ^| findstr "LISTENING"') do (
    echo Stopping node process PID %%a...
    taskkill /F /PID %%a
)
echo Server stopped.
