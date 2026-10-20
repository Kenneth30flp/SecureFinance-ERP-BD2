param(
 [Parameter(Mandatory=$true)][string]$Server,
 [Parameter(Mandatory=$true)][string]$Database,
 [Parameter(Mandatory=$true)][int]$Actor,
 [Parameter(Mandatory=$true)][int]$Cliente,
 [Parameter(Mandatory=$true)][int]$Producto,
 [switch]$TrustServerCertificate
)
$ErrorActionPreference='Stop'
if ($Database -cnotmatch '^SecureFinanceERP_ParteII_Test_Kardex_[a-f0-9]{32}$') { throw 'Solo base nueva del ejecutor Kardex.' }
Add-Type -AssemblyName System.Data
$builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$builder['Data Source']=$Server
$builder['Initial Catalog']=$Database
$builder['Integrated Security']=$true
$builder['Encrypt']=$true
$builder['TrustServerCertificate']=[bool]$TrustServerCertificate
$connection=[System.Data.SqlClient.SqlConnection]::new($builder.get_ConnectionString())
try {
 $connection.Open()
 $command=$connection.CreateCommand()
 $command.CommandText="IF DB_NAME()<>@Base THROW 54900,'Contexto incorrecto.',1; DECLARE @D dbo.TipoDetalleVentaDescuento; INSERT @D VALUES(@Producto,1,0); EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId=@Cliente,@UsuarioId=@Actor,@Detalle=@D;"
 [void]$command.Parameters.AddWithValue('@Base',$Database)
 [void]$command.Parameters.AddWithValue('@Producto',$Producto)
 [void]$command.Parameters.AddWithValue('@Cliente',$Cliente)
 [void]$command.Parameters.AddWithValue('@Actor',$Actor)
 $reader=$command.ExecuteReader()
 $sets=[System.Collections.Generic.List[object]]::new()
 try {
  do {
   if ($reader.FieldCount -eq 0) { continue }
   $names=@(); $types=@(); $rows=@()
   for($i=0;$i -lt $reader.FieldCount;$i++){ $names+=$reader.GetName($i); $types+=$reader.GetFieldType($i).FullName }
   while($reader.Read()) {
    $row=[ordered]@{}
    for($i=0;$i -lt $reader.FieldCount;$i++){ $row[$names[$i]]=if($reader.IsDBNull($i)){$null}else{$reader.GetValue($i)} }
    $rows+=,[pscustomobject]$row
   }
   $sets.Add([pscustomobject]@{columns=$names;types=$types;rows=$rows})
  } while($reader.NextResult())
 } finally { $reader.Dispose() }
 [pscustomobject]@{database=$connection.Database;sets=$sets.ToArray()} | ConvertTo-Json -Depth 8 -Compress
} finally { $connection.Dispose() }
