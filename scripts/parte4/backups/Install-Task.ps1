[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SecretsFile,
 [Parameter(Mandatory=$true)][string]$RunAsUser,
 [string]$TaskName='SecureFinance-UC13',
 [string]$NodePath=(Get-Command node.exe -ErrorAction Stop).Source
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$secret=(Resolve-Path -LiteralPath $SecretsFile).Path
if(-not (Test-Path -LiteralPath $secret -PathType Leaf)){throw 'SecretsFile debe ser un archivo.'}
$NodePath=(Resolve-Path -LiteralPath $NodePath).Path
if(-not (Test-Path -LiteralPath $NodePath -PathType Leaf)){throw 'NodePath debe ser un ejecutable existente.'}
if($secret.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'El archivo secreto debe estar fuera del repositorio.'}
if(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue){throw 'Ya existe la tarea. Revise su configuracion antes de reemplazarla.'}
$runner=Join-Path $PSScriptRoot 'Run-Task.ps1'
$taskArguments='-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "'+$runner+'" -SecretsFile "'+$secret+'" -NodePath "'+$NodePath+'"'
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArguments -WorkingDirectory $repo
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12)
# S4U avoids storing a password; requires local SQL/disk access, dedicated Windows account and batch-logon right.
$principal=New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType S4U -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal
