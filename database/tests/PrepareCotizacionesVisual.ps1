# Restaurar el respaldo de demostracion en una TERCERA copia para las escrituras E2E.
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-demo.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_DEMO_[0-9]{14}_[a-f0-9]{8}$'){throw 'Origen de demostracion invalido'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-VisualCopy;Pooling=False"
function Read([string]$s){$cmd=$c.CreateCommand();$cmd.CommandText=$s;$t=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$t.Load($r);$r.Close();return ,$t}
function Run([string]$s){$cmd=$c.CreateCommand();$cmd.CommandTimeout=180;$cmd.CommandText=$s;[void]$cmd.ExecuteNonQuery()}
$c.Open()
try{
 $backup=$state.backup.Replace("'","''");Run "RESTORE VERIFYONLY FROM DISK=N'$backup' WITH CHECKSUM;"
 $files=Read "RESTORE FILELISTONLY FROM DISK=N'$backup'";$dataRoot=(Read "SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
 $visual='SecureFinanceERP_P3_COT_VISUAL_'+(Get-Date -Format 'yyyyMMddHHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
 $moves=@();$i=0;foreach($f in $files.Rows){$extension=if($f.Type -eq 'L'){'ldf'}else{'mdf'};$target=Join-Path $dataRoot "${visual}_${i}.$extension";$moves+="MOVE N'$($f.LogicalName.Replace("'","''"))' TO N'$($target.Replace("'","''"))'";$i++}
 Run "RESTORE DATABASE [$visual] FROM DISK=N'$backup' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
 $state.lab=$visual;$state|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root '.data/cotizaciones-visual.json') -Encoding UTF8
 Write-Output "PASS copia exclusiva de validacion visual: $visual; demostracion original sin escrituras de pruebas"
}finally{$c.Close()}
