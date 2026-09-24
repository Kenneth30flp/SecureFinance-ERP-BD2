USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    IF dbo.fn_CalcularIVA(100) <> 12 OR dbo.fn_CalcularIVA(0) <> 0
        THROW 51001, 'IVA incorrecto.', 1;
    IF dbo.fn_CalcularSubtotal(3, 10.50) <> 31.50
        THROW 51002, 'Subtotal incorrecto.', 1;
    IF OBJECT_ID(N'dbo.tr_Usuario_Auditar_Update', N'TR') IS NOT NULL
        THROW 51003, 'No debe existir el trigger de Usuario.', 1;

    DECLARE @Inicio BIGINT = ISNULL((SELECT MAX(BitacoraTransaccionId) FROM dbo.Bitacora_Transacciones), 0);
    DECLARE @Tag NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
    DECLARE @Productos TABLE (ProductoId INT PRIMARY KEY);
    INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock)
    OUTPUT inserted.ProductoId INTO @Productos
    VALUES (N'A' + @Tag, N'Prueba auditoria A', 10, 20),
           (N'B' + @Tag, N'Prueba auditoria B', 10, 20);
    DECLARE @Id INT = (SELECT MIN(ProductoId) FROM @Productos);
    UPDATE dbo.Producto SET Precio = 12 WHERE ProductoId = @Id;
    UPDATE dbo.Producto SET Stock = 25 WHERE ProductoId = @Id;
    UPDATE dbo.Producto SET Precio = Precio + 1, Stock = Stock + 1
    WHERE ProductoId IN (SELECT ProductoId FROM @Productos);

    DECLARE @Esperado TABLE (ProductoId INT, PrecioAnterior DECIMAL(12,2), StockAnterior INT, PrecioNuevo DECIMAL(12,2), StockNuevo INT);
    INSERT @Esperado VALUES (@Id,10,20,12,20), (@Id,12,20,12,25), (@Id,12,25,13,26);
    INSERT @Esperado SELECT ProductoId,10,20,11,21 FROM @Productos WHERE ProductoId <> @Id;
    IF (SELECT COUNT(*) FROM dbo.fn_ConsultarAuditoria(NULL,NULL,N'Producto','UPDATE')
        WHERE BitacoraTransaccionId > @Inicio) <> 4
        THROW 51004, 'UPDATE individual o multiple no auditado.', 1;
    IF EXISTS (
        SELECT 1 FROM @Esperado e WHERE NOT EXISTS (
            SELECT 1 FROM dbo.Bitacora_Transacciones b
            WHERE b.BitacoraTransaccionId > @Inicio AND b.TablaAfectada = N'Producto' AND b.Operacion = 'UPDATE'
              AND b.IdentificadorRegistro = CONVERT(NVARCHAR(4000), e.ProductoId)
              AND TRY_CONVERT(INT, JSON_VALUE(b.ValorAnterior,'$.ProductoId')) = e.ProductoId
              AND TRY_CONVERT(INT, JSON_VALUE(b.ValorNuevo,'$.ProductoId')) = e.ProductoId
              AND TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(b.ValorAnterior,'$.Precio')) = e.PrecioAnterior
              AND TRY_CONVERT(INT, JSON_VALUE(b.ValorAnterior,'$.Stock')) = e.StockAnterior
              AND TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(b.ValorNuevo,'$.Precio')) = e.PrecioNuevo
              AND TRY_CONVERT(INT, JSON_VALUE(b.ValorNuevo,'$.Stock')) = e.StockNuevo))
        THROW 51005, 'Valores anteriores/nuevos incorrectos.', 1;
    UPDATE dbo.Producto SET Precio = Precio WHERE ProductoId IN (SELECT ProductoId FROM @Productos);
    IF (SELECT COUNT(*) FROM dbo.fn_ConsultarAuditoria(NULL,NULL,N'Producto','UPDATE') WHERE BitacoraTransaccionId > @Inicio) <> 4
        THROW 51006, 'Un UPDATE sin cambios no debe auditarse.', 1;

    DELETE dbo.Producto WHERE ProductoId IN (SELECT ProductoId FROM @Productos);
    IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones b JOIN @Productos p
        ON b.IdentificadorRegistro = CONVERT(NVARCHAR(4000),p.ProductoId)
        WHERE b.BitacoraTransaccionId > @Inicio AND b.TablaAfectada = N'Producto' AND b.Operacion = 'DELETE'
          AND b.ValorNuevo IS NULL
          AND TRY_CONVERT(DECIMAL(12,2),JSON_VALUE(b.ValorAnterior,'$.Precio')) = CASE WHEN p.ProductoId = @Id THEN 13 ELSE 11 END
          AND TRY_CONVERT(INT,JSON_VALUE(b.ValorAnterior,'$.Stock')) = CASE WHEN p.ProductoId = @Id THEN 26 ELSE 21 END) <> 2
        THROW 51007, 'DELETE multiple o sus valores incorrectos.', 1;

    DECLARE @UsuarioId INT = (SELECT TOP (1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId);
    IF @UsuarioId IS NULL THROW 51008, 'Se requiere un usuario existente del seed de seguridad.', 1;
    DECLARE @Nombre NVARCHAR(150) = N'Audit ' + @Tag;
    INSERT dbo.Cliente (NIT, Nombre) VALUES (LEFT(@Tag,25), @Nombre);
    DECLARE @ClienteId INT = SCOPE_IDENTITY(), @Fecha DATETIME2(3) = SYSUTCDATETIME();
    INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, IVA, Total)
    VALUES (@ClienteId,@UsuarioId,@Fecha,100,12,112);
    DECLARE @FacturaId INT = SCOPE_IDENTITY();
    IF NOT EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones
        WHERE BitacoraTransaccionId > @Inicio AND TablaAfectada = N'Factura' AND Operacion = 'INSERT'
          AND IdentificadorRegistro = CONVERT(NVARCHAR(4000),@FacturaId) AND ValorAnterior IS NULL
          AND TRY_CONVERT(INT,JSON_VALUE(ValorNuevo,'$.FacturaId')) = @FacturaId
          AND TRY_CONVERT(DECIMAL(19,2),JSON_VALUE(ValorNuevo,'$.Total')) = 112)
        THROW 51009, 'Factura no auditada.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerHistoricoVentas(@Fecha,@Fecha,@Tag)
        WHERE Factura = @FacturaId AND Cliente = @Nombre AND Fecha = @Fecha
          AND Usuario = (SELECT NombreUsuario FROM dbo.Usuario WHERE UsuarioId = @UsuarioId)
          AND Subtotal = 100 AND IVA = 12 AND Total = 112)
        THROW 51010, 'Historico real incorrecto.', 1;
    DECLARE @Antes DATETIME2(3) = DATEADD(MILLISECOND,-1,@Fecha), @Despues DATETIME2(3) = DATEADD(MILLISECOND,1,@Fecha);
    IF EXISTS (SELECT 1 FROM dbo.fn_ObtenerHistoricoVentas(NULL,@Antes,@Tag))
       OR EXISTS (SELECT 1 FROM dbo.fn_ObtenerHistoricoVentas(@Despues,NULL,@Tag))
       OR EXISTS (SELECT 1 FROM dbo.fn_ObtenerHistoricoVentas(NULL,NULL,N'inexistente-' + @Tag))
        THROW 51011, 'Filtros del historico incorrectos.', 1;
    DECLARE @Historico TABLE (Factura INT, Fecha DATETIME2(3), Cliente NVARCHAR(150), Usuario NVARCHAR(50), Subtotal DECIMAL(19,2), IVA DECIMAL(19,2), Total DECIMAL(19,2));
    INSERT @Historico EXEC dbo.sp_ConsultarHistoricoVentas @FechaInicial=@Fecha, @FechaFinal=@Fecha, @Cliente=@Tag;
    IF (SELECT COUNT(*) FROM @Historico WHERE Factura=@FacturaId AND Total=112) <> 1
        THROW 51012, 'SP historico incorrecto.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones WHERE BitacoraTransaccionId > @Inicio
        AND (UsuarioSQL <> SUSER_SNAME() OR HostName <> HOST_NAME() OR AppName <> APP_NAME()
             OR NULLIF(UsuarioSQL,N'') IS NULL OR NULLIF(HostName,N'') IS NULL OR NULLIF(AppName,N'') IS NULL))
        THROW 51013, 'Metadatos de conexion incorrectos.', 1;
    -- Cada JSON nuevo contiene exclusivamente las columnas permitidas.
    IF EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones b
        CROSS APPLY (VALUES (b.ValorAnterior),(b.ValorNuevo)) v(JsonTexto)
        CROSS APPLY OPENJSON(v.JsonTexto) j
        WHERE b.BitacoraTransaccionId > @Inicio
          AND ((b.TablaAfectada = N'Producto' AND j.[key] NOT IN
                ('ProductoId','Codigo','Descripcion','Precio','Stock','Activo'))
            OR (b.TablaAfectada = N'Factura' AND j.[key] NOT IN
                ('FacturaId','ClienteId','UsuarioId','FechaHora','Subtotal','IVA','Total','Estado'))))
        THROW 51015, 'Se capturaron columnas no permitidas.', 1;
    IF EXISTS (SELECT 1 FROM dbo.fn_ConsultarAuditoria(NULL,NULL,N'Cliente','UPDATE') WHERE BitacoraTransaccionId > @Inicio)
        THROW 51016, 'El filtro de tabla de auditoria es incorrecto.', 1;
    -- Revisa tambien registros previos: no oculta una posible fuga historica.
    IF EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones b
        CROSS APPLY (VALUES (b.ValorAnterior),(b.ValorNuevo)) v(JsonTexto)
        CROSS JOIN (VALUES (N'Password'),(N'PasswordHash'),(N'Salt'),(N'TokenHash'),(N'SESSION_SECRET'),(N'DB_PASSWORD')) s(Secreto)
        WHERE CHARINDEX(s.Secreto, v.JsonTexto COLLATE Latin1_General_100_CI_AS) > 0)
        THROW 51014, 'Se detectaron nombres sensibles en la bitacora.', 1;
    ROLLBACK TRANSACTION;
    PRINT N'OK: Funciones, auditoría DML e histórico de ventas validados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
