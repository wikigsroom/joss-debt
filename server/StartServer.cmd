@echo off
cd /d "%~dp0"
IncenseDebtServer.exe --headless --max-fps 60 -- --config="%~dp0config.json" --data-dir="%~dp0data"
