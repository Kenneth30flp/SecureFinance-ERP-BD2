$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-lab.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_[0-9]{14}_[a-f0-9]{8}$'){throw 'Solo base de pruebas automatizadas'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=$($state.lab);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-SearchInstall;Pooling=False"
function Run([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;[void]$cmd.ExecuteNonQuery()}
$content=Get-Content (Join-Path $root 'database/44_P3_COT_BusquedaComercial.sql') -Raw -Encoding UTF8
if($content -match '(?im)^\s*USE\s'){throw 'USE prohibido'}
$c.Open();try{$cmd=$c.CreateCommand();$cmd.CommandText='SELECT DB_NAME()';if($cmd.ExecuteScalar() -ne $state.lab){throw 'Destino incorrecto'};Run 'BEGIN TRANSACTION;';try{foreach($batch in [regex]::Split($content,'(?im)^\s*GO\s*\r?$')){if($batch.Trim()){Run $batch}};Run 'COMMIT;'}catch{try{Run 'IF @@TRANCOUNT>0 ROLLBACK;'}catch{};throw};Write-Output 'PASS 44 en base de pruebas automatizadas'}finally{$c.Close()}
