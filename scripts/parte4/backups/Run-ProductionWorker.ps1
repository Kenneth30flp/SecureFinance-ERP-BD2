[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$operatorIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]::new($operatorIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run elevated: the protected runtime is intentionally inaccessible to the web identity.'}
$destination=Join-Path $env:ProgramData 'SecureFinanceERP/UC13'
& node.exe (Join-Path $destination 'run.cjs')
if($LASTEXITCODE -ne 0){throw 'Independent worker failed. Inspect its protected worker.jsonl log.'}
Write-Output 'Independent worker completed under the operator Windows token using only the dedicated SQL worker login; this does not certify the unavailable scheduled-task identity.'
