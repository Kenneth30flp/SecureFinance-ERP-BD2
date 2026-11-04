# Read-only destination probing. Roots arrive as JSON on stdin, never interpolated as code.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
Add-Type -Path (Join-Path $PSScriptRoot 'Windows-Inspection.cs')
$roots=@(ConvertFrom-Json ([Console]::In.ReadToEnd()))
if(-not $roots.Count){throw 'No backup destinations supplied.'}
$result=@(foreach($root in $roots){
 if($root -notmatch '^[A-Za-z]:\\' -or $root -match '[\r\n\x00]' -or $root -match '(^|[\\/])\.\.([\\/]|$)' -or -not [IO.Directory]::Exists($root)){throw 'Existing absolute local backup directory required.'}
 [SecureFinance.VolumeInspection]::Read($root)
})
ConvertTo-Json -InputObject $result -Compress
