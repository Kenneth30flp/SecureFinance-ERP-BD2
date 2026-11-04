param([Parameter(Mandatory=$true)][string]$SecretsFile,[Parameter(Mandatory=$true)][string]$NodePath)
$ErrorActionPreference='Stop'
$env:BACKUPS_ENV_FILE=$SecretsFile
& $NodePath (Join-Path $PSScriptRoot 'runner.js')
exit $LASTEXITCODE
