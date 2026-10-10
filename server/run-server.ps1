param(
    [int]$Port = 18777,
    [string]$Bind = '0.0.0.0',
    [string]$DataDirectory = '',
    [int]$MaxRooms = 2,
    [switch]$Source
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotExecutable = Join-Path $projectRoot '.local-tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$serverExecutable = Join-Path $projectRoot 'build/server/IncenseDebtServer.exe'
if (-not $DataDirectory) { $DataDirectory = Join-Path $PSScriptRoot 'data' }
if (-not $Source -and (Test-Path -LiteralPath $serverExecutable)) {
    & $serverExecutable --headless --max-fps 60 -- "--bind=$Bind" "--port=$Port" "--data-dir=$DataDirectory" "--max-rooms=$MaxRooms"
} else {
    if (-not (Test-Path -LiteralPath $godotExecutable)) { throw 'Build the native server or fetch Godot 4.7.2 using tools/runtime/fetch_godot.py.' }
    & $godotExecutable --headless --max-fps 60 --path (Join-Path $projectRoot 'game') --script (Join-Path $PSScriptRoot 'main.gd') -- "--bind=$Bind" "--port=$Port" "--data-dir=$DataDirectory" "--max-rooms=$MaxRooms"
}
exit $LASTEXITCODE
