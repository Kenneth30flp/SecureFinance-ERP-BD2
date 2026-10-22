$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/erp-deployment.json') -Raw|ConvertFrom-Json
$source=$state.lab
if($source -notmatch '^SecureFinanceERP_Estabilizacion_[0-9]+$'){throw 'Solo copia aislada como origen'}
$stamp=Get-Date -Format 'yyyyMMddHHmmss'
$lab="SecureFinanceERP_SKU_$stamp"
$c=New-Object System.Data.SqlClient.SqlConnection 'Server=localhost;Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True'
$c.Open()
function Run([string]$text){$cmd=$c.CreateCommand();$cmd.CommandText=$text;$cmd.CommandTimeout=180;[void]$cmd.ExecuteNonQuery()}
function Read([string]$text){$cmd=$c.CreateCommand();$cmd.CommandText=$text;$cmd.CommandTimeout=180;$dt=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$dt.Load($r);$r.Close();return ,$dt}
try{
 $backupRoot=(Read "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultBackupPath')) P").Rows[0].P
 $backup=Join-Path $backupRoot "$lab.bak"
 Run "BACKUP DATABASE [$source] TO DISK=N'$backup' WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=N'$backup' WITH CHECKSUM;"
 $files=Read "RESTORE FILELISTONLY FROM DISK=N'$backup'"
 $dataRoot=(Read "SELECT CONVERT(nvarchar(200),SERVERPROPERTY('InstanceDefaultDataPath')) P").Rows[0].P
 $moves=@();$i=0
 foreach($row in $files.Rows){$ext=if($row.Type -eq 'L'){'ldf'}else{'mdf'};$path=Join-Path $dataRoot "${lab}_${i}.$ext";$moves+="MOVE N'$($row.LogicalName)' TO N'$path'";$i++}
 Run "RESTORE DATABASE [$lab] FROM DISK=N'$backup' WITH CHECKSUM,RECOVERY,$($moves -join ',');"
 @{database=$lab;source=$source}|ConvertTo-Json|Set-Content (Join-Path $root '.data/product-sku-lab.json') -Encoding UTF8
}finally{$c.Close()}
# Capture historical data, apply only incremental 38, assert complete preservation.
$sql=@"
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME()<>N'$lab' THROW 54900,'Solo laboratorio SKU.',1;
SELECT * INTO #Products FROM dbo.Producto;
SELECT COUNT_BIG(*) N INTO #Invoices FROM dbo.Factura;
SELECT COUNT_BIG(*) N INTO #Kardex FROM dbo.Kardex_Inventario;
GO
:r database/38_ERP_ProductoSKUAutomatico.sql
IF EXISTS(SELECT * FROM dbo.Producto EXCEPT SELECT * FROM #Products)
 OR EXISTS(SELECT * FROM #Products EXCEPT SELECT * FROM dbo.Producto)
 OR (SELECT COUNT_BIG(*) FROM dbo.Factura)<>(SELECT N FROM #Invoices)
 OR (SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario)<>(SELECT N FROM #Kardex)
 THROW 54900,'Migracion modifica historicos.',1;
DBCC CHECKDB WITH NO_INFOMSGS;
PRINT 'PASS migracion 38 e integridad; productos y relaciones historicas preservados';
"@
$file=Join-Path $root '.data/product-sku-migration.sql'
[IO.File]::WriteAllText($file,$sql,(New-Object Text.UTF8Encoding($false)))
& sqlcmd -S localhost -E -C -b -d $lab -i $file -f 65001
if($LASTEXITCODE -ne 0){throw 'Fallo validacion de migracion 38'}
Write-Output "PASS copia SKU $lab"
