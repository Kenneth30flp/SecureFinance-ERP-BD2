param(
 [switch]$AuthorizeSqlWrites,
 [string]$ExpectedServer = ($env:COMPUTERNAME + '\SQLEXPRESS')
)
$ErrorActionPreference = 'Stop'
# Sin Docker, sin respaldo, sin credenciales persistidas ni autenticacion Windows.
if(-not $AuthorizeSqlWrites) {
 Write-Output 'Preparado para SQL Express. No se abren conexiones ni se escribe SQL sin -AuthorizeSqlWrites.'
 Write-Output 'Requiere login SQL dedicado: CONNECT SQL, VIEW ANY DATABASE y CREATE ANY DATABASE; sin roles ni acceso a bases anteriores.'
 exit 0
}
$labCredential = Get-Credential -Message 'Login SQL dedicado del laboratorio, sin acceso a otras bases. No usar sa ni la cuenta de la aplicacion.'
if($null -eq $labCredential) { throw 'Credencial requerida.' }
$names = @('COMPRAS_SQL_WRITE_AUTHORIZATION','COMPRAS_LAB_SERVER','COMPRAS_LAB_INSTANCE','COMPRAS_LAB_EXPECTED_SERVER','COMPRAS_LAB_USER','COMPRAS_LAB_PASSWORD')
$previous = @{}
foreach($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
 $env:COMPRAS_SQL_WRITE_AUTHORIZATION='LAB_NUEVO_AISLADO'
 $env:COMPRAS_LAB_SERVER='localhost'
 $env:COMPRAS_LAB_INSTANCE='SQLEXPRESS'
 $env:COMPRAS_LAB_EXPECTED_SERVER=$ExpectedServer
 $env:COMPRAS_LAB_USER=$labCredential.UserName
 $env:COMPRAS_LAB_PASSWORD=$labCredential.GetNetworkCredential().Password
 & node (Join-Path $PSScriptRoot '..\database\tests\ComprasIntegration.js') --execute-new-lab
 if($LASTEXITCODE -ne 0) { throw 'Laboratorio no completado. Ninguna base preexistente es un destino permitido.' }
} finally {
 foreach($name in $names) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
 $labCredential=$null
}
