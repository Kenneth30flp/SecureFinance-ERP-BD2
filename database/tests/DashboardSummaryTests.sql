USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Admin INT = (SELECT TOP (1) ur.UsuarioId FROM dbo.Usuario_Rol ur
 JOIN dbo.Usuario u ON u.UsuarioId = ur.UsuarioId AND u.Activo = 1
 JOIN dbo.Rol r ON r.RolId = ur.RolId WHERE r.Nombre = N'Administrador' AND r.Activo = 1),
 @Client INT = (SELECT MIN(ClienteId) FROM dbo.Cliente),
 @Day DATE = CONVERT(DATE, DATEADD(HOUR, -6, SYSUTCDATETIME())), @Start DATETIME2(3), @End DATETIME2(3);
SET @Start = DATEADD(HOUR, 6, CONVERT(DATETIME2(3), @Day)); SET @End = DATEADD(DAY, 1, @Start);
DECLARE @Result TABLE (VentasDia VARCHAR(40), FacturasDia VARCHAR(20), ProductosStockBajo VARCHAR(20),
 EventosDMLDia VARCHAR(20), FechaOperacion VARCHAR(10), RolesActuales NVARCHAR(MAX));
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT @Result EXEC dbo.sp_ObtenerResumenDashboard @Admin;
 DECLARE @Sales DECIMAL(38,2), @Invoices BIGINT, @Stock BIGINT;
 SELECT @Sales = CONVERT(DECIMAL(38,2), VentasDia), @Invoices = CONVERT(BIGINT, FacturasDia),
  @Stock = CONVERT(BIGINT, ProductosStockBajo) FROM @Result;
 IF NOT EXISTS (SELECT 1 FROM @Result WHERE FechaOperacion = CONVERT(VARCHAR(10), @Day, 23)
  AND RolesActuales LIKE N'%Administrador%') THROW 52710, 'Dashboard day or roles incorrect.', 1;
 INSERT dbo.Producto(Codigo, Descripcion, Precio, Stock, Activo)
 VALUES (N'DASH-LOW-TEST', N'Dashboard fixture', 1, 5, 1), (N'DASH-OFF-TEST', N'Dashboard fixture', 1, 0, 0);
 INSERT dbo.Factura(ClienteId, UsuarioId, FechaHora, Subtotal, IVA, Total)
 VALUES (@Client, @Admin, DATEADD(MILLISECOND,-1,@Start),10,0,10),
  (@Client, @Admin, @Start,20,0,20), (@Client, @Admin, DATEADD(MILLISECOND,-1,@End),30,0,30),
  (@Client, @Admin, @End,40,0,40);
 DELETE @Result; INSERT @Result EXEC dbo.sp_ObtenerResumenDashboard @Admin;
 IF NOT EXISTS (SELECT 1 FROM @Result WHERE CONVERT(DECIMAL(38,2),VentasDia) = @Sales + 50
  AND CONVERT(BIGINT,FacturasDia) = @Invoices + 2 AND CONVERT(BIGINT,ProductosStockBajo) = @Stock + 1
  AND CONVERT(BIGINT,EventosDMLDia) = (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones
    WHERE FechaHora >= @Start AND FechaHora < @End)) THROW 52711, 'Dashboard totals or UTC boundaries incorrect.', 1;
 DECLARE @Cashier INT = (SELECT TOP (1) ur.UsuarioId FROM dbo.Usuario_Rol ur JOIN dbo.Rol r ON r.RolId = ur.RolId
  WHERE r.Nombre = N'Cajero' AND NOT EXISTS (SELECT 1 FROM dbo.Usuario_Rol x JOIN dbo.Rol y ON y.RolId = x.RolId
   WHERE x.UsuarioId = ur.UsuarioId AND y.Nombre IN (N'Administrador', N'Auditor')));
 IF @Cashier IS NOT NULL
 BEGIN
  DELETE @Result; INSERT @Result EXEC dbo.sp_ObtenerResumenDashboard @Cashier;
  IF NOT EXISTS (SELECT 1 FROM @Result WHERE VentasDia IS NOT NULL AND EventosDMLDia IS NULL)
   THROW 52712, 'Dashboard exposed restricted audit metrics.', 1;
 END;
 DELETE dbo.Usuario_Rol WHERE UsuarioId = @Admin;
 DELETE @Result; INSERT @Result EXEC dbo.sp_ObtenerResumenDashboard @Admin;
 IF EXISTS (SELECT 1 FROM @Result WHERE VentasDia IS NOT NULL OR FacturasDia IS NOT NULL
  OR ProductosStockBajo IS NOT NULL OR EventosDMLDia IS NOT NULL OR RolesActuales IS NOT NULL)
  THROW 52713, 'Dashboard ignored current SQL permissions.', 1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
BEGIN TRY
 EXEC dbo.sp_ObtenerResumenDashboard -1;
 THROW 52714, 'Unknown user accepted.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 52701 THROW; END CATCH;
PRINT N'OK: Dashboard totals, UTC boundaries, stock threshold, current roles and authorization.';
GO
