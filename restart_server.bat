@echo off
call "%~dp0stop_server.bat"
timeout /t 2 /nobreak >nul
call "%~dp0start_server.bat"
