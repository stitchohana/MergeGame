@echo off
set DATA_DIR="%~dp0server\data"
if exist %DATA_DIR% (
    rmdir /s /q %DATA_DIR%
    echo Server data cleared: %DATA_DIR%
) else (
    echo No server data directory found.
)
