$ErrorActionPreference = 'Stop'
$serverData = Join-Path $PSScriptRoot 'data'
if (-not (Test-Path -LiteralPath $serverData -PathType Container)) { throw 'This server data directory does not exist.' }
Set-Content -LiteralPath (Join-Path $serverData 'stop') -Value 'graceful stop requested' -Encoding utf8
