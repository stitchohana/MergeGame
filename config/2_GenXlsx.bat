@echo off
cd /d "%~dp0"
where python >nul 2>nul
if not errorlevel 1 (
	python json_to_xlsx.py
) else (
	py -3 json_to_xlsx.py
)
set "exit_code=%errorlevel%"
pause
exit /b %exit_code%
