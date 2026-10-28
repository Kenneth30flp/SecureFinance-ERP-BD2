# Puente de pruebas por stdin. No se importa desde la aplicacion.
$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/cotizaciones-lab.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_P3_COT_[0-9]{14}_[a-f0-9]{8}$'){throw 'Solo laboratorio Cotizaciones'}
$c=New-Object System.Data.SqlClient.SqlConnection "Server=$($state.server);Database=$($state.lab);Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=SecureFinance-Cotizaciones-TestAdmin;Pooling=False"
$c.Open()
try{
 $identity=$c.CreateCommand();$identity.CommandText='SELECT DB_NAME()';if($identity.ExecuteScalar() -ne $state.lab){throw 'Identidad SQL incorrecta'}
 while($null -ne ($line=[Console]::ReadLine())){
  try{
   $inputQuery=$line|ConvertFrom-Json
   if($inputQuery.sql -match '(?im)^\s*USE\s' -or $inputQuery.sql -match '(?i)\[?SecureFinanceERP\]?\s*\.'){throw 'Cambio de contexto o acceso a principal prohibido'}
   $cmd=$c.CreateCommand();$cmd.CommandTimeout=40;$cmd.CommandText=$inputQuery.sql
   $reader=$cmd.ExecuteReader();$sets=New-Object 'System.Collections.Generic.List[object]'
   try{
    do{
     if($reader.FieldCount -gt 0){
      $rows=New-Object 'System.Collections.Generic.List[object]'
      while($reader.Read()){
       $row=[ordered]@{}
       for($i=0;$i -lt $reader.FieldCount;$i++){
        $value=$reader.GetValue($i)
        if($value -is [DBNull]){$value=$null}
        elseif($value -is [byte[]]){$value=([BitConverter]::ToString($value)).Replace('-','')}
        elseif($value -is [decimal]){$value=$value.ToString([Globalization.CultureInfo]::InvariantCulture)}
        elseif($value -is [datetime]){$value=$value.ToString('o')+'Z'}
        $row[$reader.GetName($i)]=$value
       }
       $rows.Add([pscustomobject]$row)
      }
      $sets.Add($rows.ToArray())
     }
    }while($reader.NextResult())
   }finally{$reader.Close()}
   $response=@{id=$inputQuery.id;sets=$sets.ToArray()}
  }catch{
   $exception=$_.Exception
   while($exception.InnerException){$exception=$exception.InnerException}
   $response=@{id=$inputQuery.id;error=$exception.Message;number=$exception.Number}
  }
  [Console]::WriteLine((ConvertTo-Json -InputObject $response -Depth 30 -Compress))
 }
}finally{$c.Close()}
