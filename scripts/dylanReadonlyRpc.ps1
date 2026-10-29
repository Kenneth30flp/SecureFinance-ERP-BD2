$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName System.Data
$allowed = @('dbo.P3_DDL_ConsultarBitacora','dbo.P3_DDL_ConsultarDetalle','dbo.P3_CRE_Consultar','dbo.P3_CRE_ConsultarCaja','dbo.P3_CRE_ConsultarRecibo','dbo.P3_BOD_Autorizar','dbo.P3_BOD_Consultar','dbo.P3_BOD_ConsultarOperacion')
function Read-Sets($command) {
    $sets = New-Object System.Collections.ArrayList
    $reader = $command.ExecuteReader()
    try {
        do {
            if ($reader.FieldCount -eq 0) { continue }
            $rows = New-Object System.Collections.ArrayList
            while ($reader.Read()) {
                $row = [ordered]@{}
                for ($i=0; $i -lt $reader.FieldCount; $i++) {
                    $value = $reader.GetValue($i)
                    if ($value -is [DBNull]) { $value = $null }
                    elseif ($value -is [DateTime]) { $value = [DateTime]::SpecifyKind($value,[DateTimeKind]::Utc).ToString('o') }
                    elseif ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
                    elseif ($value -is [long]) { $value = $value.ToString([Globalization.CultureInfo]::InvariantCulture) }
                    $row[$reader.GetName($i)] = $value
                }
                [void]$rows.Add($row)
            }
            [void]$sets.Add(@($rows.ToArray()))
        } while ($reader.NextResult())
    } finally { $reader.Dispose() }
    return ,($sets.ToArray())
}
while ($null -ne ($line = [Console]::ReadLine())) {
    $connection = $null; $impersonated = $false; $id = $null
    try {
        $rpc = $line | ConvertFrom-Json
        $id = $rpc.id
        if ($rpc.op -ne 'bootstrap' -and ($rpc.op -ne 'execute' -or $allowed -cnotcontains $rpc.proc)) { throw 'RPC not allowed' }
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $builder.set_DataSource('localhost')
        $builder.set_InitialCatalog('SecureFinanceERP_Lab_Dylan')
        $builder.set_IntegratedSecurity($true)
        $builder.set_Encrypt($true)
        $builder.set_TrustServerCertificate($true)
        $builder.set_ApplicationName('Dylan-Readonly-QA-RPC')
        $builder.set_ConnectTimeout(15)
        $builder.set_Pooling($false)
        $connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
        $connection.Open()
        $guard = $connection.CreateCommand()
        $guard.CommandText = "SELECT CASE WHEN CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) COLLATE Latin1_General_100_BIN2=N'DESKTOP-HBNSH7J' AND DB_NAME() COLLATE Latin1_General_100_BIN2=N'SecureFinanceERP_Lab_Dylan' AND @@TRANCOUNT=0 AND EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'securefinance_app' AND sid=SUSER_SID(N'SecureFinanceAppRuntime')) THEN 1 ELSE 0 END"
        if ($guard.ExecuteScalar() -ne 1) { throw 'Destination guard rejected' }
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 20
        if ($rpc.op -eq 'bootstrap') {
            # Only synthetic actor identity and active role permission codes, never credentials.
            $command.CommandText = "SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN' AND Activo=1; SELECT DISTINCT p.Codigo FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId JOIN dbo.Rol r ON r.RolId=ur.RolId AND r.Activo=1 JOIN dbo.Rol_Permiso rp ON rp.RolId=r.RolId JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId AND p.Activo=1 WHERE u.NombreUsuario=N'P3_DYLAN_QA_ADMIN' AND u.Activo=1;"
            $sets = Read-Sets $command
            $result = @{recordsets=$sets;guard=$true;bootstrap=$true}
        } else {
            $command.CommandText = "EXECUTE AS USER = 'securefinance_app'"
            [void]$command.ExecuteNonQuery(); $impersonated = $true
            $command.CommandText = "SELECT CASE WHEN USER_NAME()=N'securefinance_app' AND IS_ROLEMEMBER(N'db_owner')=0 AND HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CONTROL')=0 THEN 1 ELSE 0 END"
            if ($command.ExecuteScalar() -ne 1) { throw 'Application token guard rejected' }
            $command.CommandType = [System.Data.CommandType]::StoredProcedure
            $command.CommandText = $rpc.proc
            foreach ($p in $rpc.params) {
                if ($p.name -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$' -or $p.type -cnotin @('Int','BigInt','NVarChar','VarChar','DateTime2','DateTime','Date','Binary','VarBinary','Bit','UniqueIdentifier','Decimal')) { throw 'Invalid parameter' }
                $parameter = $command.Parameters.Add('@'+$p.name, [System.Data.SqlDbType]::$($p.type))
                if ($p.length -gt 0) { $parameter.Size = $p.length }
                $value = $p.value
                if ($null -eq $value) { $value = [DBNull]::Value }
                elseif ($p.type -in @('DateTime2','DateTime','Date')) { $value = [DateTime]::Parse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind) }
                elseif ($p.type -in @('Binary','VarBinary')) { $value = [Convert]::FromBase64String($value) }
                elseif ($p.type -eq 'BigInt') { $value = [long]::Parse($value) }
                elseif ($p.type -eq 'UniqueIdentifier') { $value = [Guid]::Parse($value) }
                $parameter.Value = $value
            }
            $sets = Read-Sets $command
            $result = @{recordsets=$sets;guard=$true;applicationToken=$true}
        }
        $response = @{id=$id;ok=$true;result=$result}
    } catch {
        $number = 0; $exception = $_.Exception
        while ($exception) { if ($exception -is [System.Data.SqlClient.SqlException]) { $number=$exception.Number; break }; $exception=$exception.InnerException }
        $response = @{id=$id;ok=$false;error=@{number=$number;message='Readonly QA RPC failed'}}
    } finally {
        if ($connection) {
            if ($impersonated -and $connection.State -eq 'Open') {
                try { $revert=$connection.CreateCommand(); $revert.CommandText='REVERT'; [void]$revert.ExecuteNonQuery() } catch { $response=@{id=$id;ok=$false;error=@{number=0;message='QA token cleanup failed'}} }
            }
            $connection.Dispose()
        }
    }
    [Console]::WriteLine((ConvertTo-Json -InputObject $response -Depth 30 -Compress))
}
