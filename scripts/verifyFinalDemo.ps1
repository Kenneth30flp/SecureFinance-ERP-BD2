param([switch]$Compare)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-demo.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_DEMO_[0-9]{14}_[a-f0-9]{8}$'){throw 'Destino no permitido'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=$($state.lab);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Final-ReadOnly;Pooling=False"
$c.Open()
try{
 $cmd=$c.CreateCommand();$cmd.CommandText=@'
SELECT DB_NAME() Nombre,
 (SELECT COUNT(*) FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=6 AND FacturaId=7011 AND Estado='PROCESADA') Documento,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),
 (SELECT * FROM dbo.P3_COT_Cotizacion ORDER BY CotizacionId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) Cotizaciones,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),
 (SELECT * FROM dbo.Factura ORDER BY FacturaId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) Facturas,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),
 (SELECT * FROM dbo.Producto ORDER BY ProductoId FOR JSON PATH,INCLUDE_NULL_VALUES))),2) Productos
'@
 $t=New-Object System.Data.DataTable;$r=$cmd.ExecuteReader();$t.Load($r);$r.Close()
 $row=$t.Rows[0];if($row.Nombre -ne $state.lab -or $row.Documento -ne 1){throw 'No coincide COT-6/factura 7011 o DB_NAME'}
 $report=@{database=[string]$row.Nombre;cot6Factura7011=$true;cotizaciones=[string]$row.Cotizaciones;facturas=[string]$row.Facturas;productos=[string]$row.Productos;mode='SELECT_ONLY'}
 $file=Join-Path $root '.data/final-demo-baseline.json'
 if($Compare){$before=Get-Content $file -Raw|ConvertFrom-Json;foreach($key in @('database','cotizaciones','facturas','productos')){if($report[$key] -ne $before.$key){throw "Cambio detectado: $key"}};$report.preserved=$true
 $folder=Join-Path $root 'docs/parte3/cierre-final';$report|ConvertTo-Json|Set-Content (Join-Path $folder 'demostracion-preservada.json') -Encoding UTF8
 }elseif(Test-Path $file){throw 'Ya existe baseline; usa -Compare'}else{$report|ConvertTo-Json|Set-Content $file -Encoding UTF8}
 $report|ConvertTo-Json
}finally{$c.Close()}
