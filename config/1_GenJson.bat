@echo off
cd /d "%~dp0"
where python >nul 2>nul
if not errorlevel 1 (
	python xlsx_to_json.py
) else (
	py -3 xlsx_to_json.py
)
set "exit_code=%errorlevel%"
pause
exit /b %exit_code%
