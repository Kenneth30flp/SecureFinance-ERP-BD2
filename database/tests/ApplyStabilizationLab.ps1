param([string]$Database='SecureFinanceERP_Estabilizacion_20261021')
$ErrorActionPreference='Stop'
if($Database -notmatch '^SecureFinanceERP_Estabilizacion_[0-9]+$'){throw 'Destino fuera del laboratorio autorizado'}
$databaseRoot=Split-Path $PSScriptRoot -Parent
# La copia restaurada requiere las migraciones de posventa/analitica posteriores al respaldo.
# Nunca ejecutar Full ni cambiar el contexto de destino.
foreach($number in @(24,25,26,30,31,32,33,34,35,36,37)){
 $file=Get-ChildItem -LiteralPath $databaseRoot -Filter "${number}_*.sql"
 if($file.Count -ne 1){throw "Migracion ambigua o ausente: $number"}
 $content=Get-Content -LiteralPath $file.FullName -Raw
 if($content -match '(?im)^\s*USE\s'){throw 'Migracion cambia contexto'}
 & sqlcmd -S localhost -E -C -b -d $Database -i $file.FullName -f 65001
 if($LASTEXITCODE -ne 0){throw "Fallo migracion $number"}
 Write-Output "PASS migracion $number"
}
