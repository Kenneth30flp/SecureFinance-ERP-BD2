USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Bitacora_Transacciones', N'U') IS NULL
BEGIN
    THROW 51000, 'La tabla dbo.Bitacora_Transacciones debe existir antes de crear los triggers de auditoría.', 1;
END;
GO

IF OBJECT_ID(N'dbo.Producto', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.tr_Producto_Auditar_Update', N'TR') IS NOT NULL
        DROP TRIGGER dbo.tr_Producto_Auditar_Update;
    GO

    CREATE TRIGGER dbo.tr_Producto_Auditar_Update
    ON dbo.Producto
    AFTER UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;

        INSERT INTO dbo.Bitacora_Transacciones (
            FechaHora,
            TablaAfectada,
            Operacion,
            UsuarioSQL,
            HostName,
            AppName,
            IdentificadorRegistro,
            ValorAnterior,
            ValorNuevo
        )
        SELECT
            SYSUTCDATETIME(),
            N'Producto',
            N'UPDATE',
            SUSER_SNAME(),
            HOST_NAME(),
            APP_NAME(),
            CONVERT(NVARCHAR(4000), CAST(i.ProductoId AS NVARCHAR(50))),
            (SELECT d.* FROM deleted AS d WHERE d.ProductoId = i.ProductoId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            (SELECT i2.* FROM inserted AS i2 WHERE i2.ProductoId = i.ProductoId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM inserted AS i
        WHERE EXISTS (
            SELECT 1
            FROM deleted AS d
            WHERE d.ProductoId = i.ProductoId
              AND (d.Precio <> i.Precio OR d.Stock <> i.Stock)
        );
    END;
    GO

    IF OBJECT_ID(N'dbo.tr_Producto_Auditar_Delete', N'TR') IS NOT NULL
        DROP TRIGGER dbo.tr_Producto_Auditar_Delete;
    GO

    CREATE TRIGGER dbo.tr_Producto_Auditar_Delete
    ON dbo.Producto
    AFTER DELETE
    AS
    BEGIN
        SET NOCOUNT ON;

        INSERT INTO dbo.Bitacora_Transacciones (
            FechaHora,
            TablaAfectada,
            Operacion,
            UsuarioSQL,
            HostName,
            AppName,
            IdentificadorRegistro,
            ValorAnterior,
            ValorNuevo
        )
        SELECT
            SYSUTCDATETIME(),
            N'Producto',
            N'DELETE',
            SUSER_SNAME(),
            HOST_NAME(),
            APP_NAME(),
            CONVERT(NVARCHAR(4000), CAST(d.ProductoId AS NVARCHAR(50))),
            (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            NULL
        FROM deleted AS d;
    END;
    GO
END;
GO

IF OBJECT_ID(N'dbo.Usuario', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.tr_Usuario_Auditar_Update', N'TR') IS NOT NULL
        DROP TRIGGER dbo.tr_Usuario_Auditar_Update;
    GO

    CREATE TRIGGER dbo.tr_Usuario_Auditar_Update
    ON dbo.Usuario
    AFTER UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;

        INSERT INTO dbo.Bitacora_Transacciones (
            FechaHora,
            TablaAfectada,
            Operacion,
            UsuarioSQL,
            HostName,
            AppName,
            IdentificadorRegistro,
            ValorAnterior,
            ValorNuevo
        )
        SELECT
            SYSUTCDATETIME(),
            N'Usuario',
            N'UPDATE',
            SUSER_SNAME(),
            HOST_NAME(),
            APP_NAME(),
            CONVERT(NVARCHAR(4000), CAST(i.UsuarioId AS NVARCHAR(50))),
            (SELECT d.* FROM deleted AS d WHERE d.UsuarioId = i.UsuarioId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            (SELECT i2.* FROM inserted AS i2 WHERE i2.UsuarioId = i.UsuarioId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM inserted AS i
        WHERE EXISTS (
            SELECT 1
            FROM deleted AS d
            WHERE d.UsuarioId = i.UsuarioId
              AND (d.NombreUsuario <> i.NombreUsuario OR d.Correo <> i.Correo OR d.Activo <> i.Activo)
        );
    END;
    GO
END;
GO
