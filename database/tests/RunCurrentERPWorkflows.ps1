$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$state=Get-Content (Join-Path $root '.data/erp-deployment.json') -Raw|ConvertFrom-Json
if($state.lab -notmatch '^SecureFinanceERP_Estabilizacion_[0-9]+$' -or -not $state.labPassed){throw 'Laboratorio no validado'}
# The current backup uses SKU CABLE, not the historical laboratory fixture DEMO-CABLE.
# Only fixture identifiers and the exact isolated database guard are substituted.
# All stock, rollback, permissions and financial assertions remain intact.
foreach($name in @('StabilizationTests','StabilizationRegression','StabilizationEdgeCases')){
 $source=Get-Content (Join-Path $PSScriptRoot "$name.sql") -Raw -Encoding UTF8
 $source=$source.Replace('SecureFinanceERP_Estabilizacion_20261021',$state.lab).Replace("Codigo='DEMO-CABLE'","Codigo='CABLE'")
 $file=Join-Path $root ".data/current-$name.sql"
 [IO.File]::WriteAllText($file,$source,(New-Object Text.UTF8Encoding($false)))
 $output=Join-Path $root ".data/current-$name.txt"
 & sqlcmd -S localhost -E -C -b -d $state.lab -i $file -f 65001 -o $output
 if($LASTEXITCODE -ne 0){Get-Content $output -Tail 15;throw "Fallo $name"}
 Get-Content $output|Select-String '^PASS '
}
$state|Add-Member -NotePropertyName workflowsPassed -NotePropertyValue $true -Force
$state|ConvertTo-Json -Depth 8|Set-Content (Join-Path $root '.data/erp-deployment.json') -Encoding UTF8
