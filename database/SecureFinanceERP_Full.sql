-- Instalación NUEVA de SecureFinance ERP.
-- Incluye seguridad, RBAC, negocio, ventas, auditoría y semillas DEMO.
-- No es una migración. No ejecutar sobre una instalación existente con las tablas ya creadas.
-- No crea passwords ni logins de servidor. El login securefinance_app se configura externamente.
-- Las fechas se almacenan en UTC donde aplica.
-- Las credenciales DEMO son exclusivamente académicas.
-- Ejecutar con una cuenta administradora en SSMS o sqlcmd; detener la ejecución ante errores.
-- Copia íntegra de los scripts modulares indicados en cada bloque, sin archivos de pruebas.

-- =========================================================
-- Fuente: database/01_CreateDatabase.sql
-- =========================================================
-- Ejecutar en SSMS con una cuenta autorizada para crear bases de datos.
USE [master];
GO
IF DB_ID(N'SecureFinanceERP') IS NULL
BEGIN
    CREATE DATABASE [SecureFinanceERP];
END;
GO

-- =========================================================
-- Fuente: database/02_SecurityTables.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO
-- Instalación inicial: ejecutar una sola vez. No elimina ni reemplaza tablas.
-- Fechas en UTC; dbo simplifica la integración con los módulos del equipo.
BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE dbo.Usuario (
        UsuarioId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Usuario PRIMARY KEY,
        NombreUsuario NVARCHAR(50) NOT NULL,
        NombreCompleto NVARCHAR(150) NOT NULL,
        Correo NVARCHAR(254) NOT NULL,
        -- SHA2_512 produce 64 bytes. VARBINARY + CHECK evita aceptar hashes cortos.
        PasswordHash VARBINARY(64) NOT NULL,
        Salt VARBINARY(32) NOT NULL CONSTRAINT DF_Usuario_Salt DEFAULT CRYPT_GEN_RANDOM(32),
        Activo BIT NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT (1),
        DebeCambiarPassword BIT NOT NULL CONSTRAINT DF_Usuario_DebeCambiarPassword DEFAULT (1),
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Usuario_FechaCreacion DEFAULT SYSUTCDATETIME(),
        FechaCambioPassword DATETIME2(3) NULL,
        CONSTRAINT UQ_Usuario_NombreUsuario UNIQUE (NombreUsuario),
        CONSTRAINT UQ_Usuario_Correo UNIQUE (Correo),
        CONSTRAINT UQ_Usuario_Salt UNIQUE (Salt),
        CONSTRAINT CK_Usuario_NombreUsuario CHECK (LEN(LTRIM(RTRIM(NombreUsuario))) > 0),
        CONSTRAINT CK_Usuario_NombreCompleto CHECK (LEN(LTRIM(RTRIM(NombreCompleto))) > 0),
        CONSTRAINT CK_Usuario_Correo CHECK (LEN(LTRIM(RTRIM(Correo))) > 0),
        CONSTRAINT CK_Usuario_Hash CHECK (DATALENGTH(PasswordHash) = 64),
        CONSTRAINT CK_Usuario_Salt CHECK (DATALENGTH(Salt) = 32),
        CONSTRAINT CK_Usuario_FechaCambio CHECK (FechaCambioPassword IS NULL OR FechaCambioPassword >= FechaCreacion)
    );

    CREATE TABLE dbo.Rol (
        RolId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Rol PRIMARY KEY,
        Nombre NVARCHAR(50) NOT NULL CONSTRAINT UQ_Rol_Nombre UNIQUE,
        Descripcion NVARCHAR(250) NULL,
        Activo BIT NOT NULL CONSTRAINT DF_Rol_Activo DEFAULT (1),
        CONSTRAINT CK_Rol_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
    );

    CREATE TABLE dbo.Permiso (
        PermisoId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Permiso PRIMARY KEY,
        Codigo NVARCHAR(100) NOT NULL CONSTRAINT UQ_Permiso_Codigo UNIQUE,
        Descripcion NVARCHAR(250) NULL,
        Activo BIT NOT NULL CONSTRAINT DF_Permiso_Activo DEFAULT (1),
        CONSTRAINT CK_Permiso_Codigo CHECK (LEN(LTRIM(RTRIM(Codigo))) > 0)
    );

    CREATE TABLE dbo.Usuario_Rol (
        UsuarioId INT NOT NULL,
        RolId INT NOT NULL,
        FechaAsignacion DATETIME2(3) NOT NULL CONSTRAINT DF_UsuarioRol_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Usuario_Rol PRIMARY KEY (UsuarioId, RolId),
        CONSTRAINT FK_UsuarioRol_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT FK_UsuarioRol_Rol FOREIGN KEY (RolId) REFERENCES dbo.Rol(RolId)
    );
    CREATE INDEX IX_UsuarioRol_Rol ON dbo.Usuario_Rol(RolId);

    CREATE TABLE dbo.Rol_Permiso (
        RolId INT NOT NULL,
        PermisoId INT NOT NULL,
        CONSTRAINT PK_Rol_Permiso PRIMARY KEY (RolId, PermisoId),
        CONSTRAINT FK_RolPermiso_Rol FOREIGN KEY (RolId) REFERENCES dbo.Rol(RolId),
        CONSTRAINT FK_RolPermiso_Permiso FOREIGN KEY (PermisoId) REFERENCES dbo.Permiso(PermisoId)
    );
    CREATE INDEX IX_RolPermiso_Permiso ON dbo.Rol_Permiso(PermisoId);

    CREATE TABLE dbo.Token_Recuperacion (
        TokenRecuperacionId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Token_Recuperacion PRIMARY KEY,
        UsuarioId INT NOT NULL,
        TokenHash VARBINARY(64) NOT NULL CONSTRAINT UQ_TokenRecuperacion_Hash UNIQUE,
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_TokenRecuperacion_Fecha DEFAULT SYSUTCDATETIME(),
        FechaExpiracion DATETIME2(3) NOT NULL,
        FechaUso DATETIME2(3) NULL,
        Invalidado BIT NOT NULL CONSTRAINT DF_TokenRecuperacion_Invalidado DEFAULT (0),
        CONSTRAINT FK_TokenRecuperacion_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_TokenRecuperacion_Hash CHECK (DATALENGTH(TokenHash) = 64),
        CONSTRAINT CK_TokenRecuperacion_Expiracion CHECK (FechaExpiracion > FechaCreacion),
        CONSTRAINT CK_TokenRecuperacion_Uso CHECK (FechaUso IS NULL OR (FechaUso >= FechaCreacion AND FechaUso < FechaExpiracion))
    );
    CREATE INDEX IX_TokenRecuperacion_Usuario ON dbo.Token_Recuperacion(UsuarioId, FechaExpiracion);

    CREATE TABLE dbo.Bitacora_Acceso (
        BitacoraAccesoId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bitacora_Acceso PRIMARY KEY,
        UsuarioId INT NULL,
        NombreUsuarioIntentado NVARCHAR(50) NOT NULL,
        Resultado VARCHAR(30) NOT NULL,
        FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_BitacoraAcceso_Fecha DEFAULT SYSUTCDATETIME(),
        HostName NVARCHAR(128) NULL CONSTRAINT DF_BitacoraAcceso_Host DEFAULT HOST_NAME(),
        AppName NVARCHAR(128) NULL CONSTRAINT DF_BitacoraAcceso_App DEFAULT APP_NAME(),
        UsuarioSQL NVARCHAR(128) NULL CONSTRAINT DF_BitacoraAcceso_UsuarioSQL DEFAULT SUSER_SNAME(),
        -- La IP SQL corresponde al backend, no necesariamente al navegador.
        IpConexionSQL VARCHAR(48) NULL CONSTRAINT DF_BitacoraAcceso_IP DEFAULT CONVERT(VARCHAR(48), CONNECTIONPROPERTY('client_net_address')),
        IpClienteAplicacion VARCHAR(45) NULL,
        CONSTRAINT FK_BitacoraAcceso_Usuario FOREIGN KEY (UsuarioId) REFERENCES dbo.Usuario(UsuarioId),
        CONSTRAINT CK_BitacoraAcceso_Resultado CHECK (Resultado IN ('EXITOSO', 'PASSWORD_INCORRECTA', 'USUARIO_INEXISTENTE', 'USUARIO_INACTIVO')),
        CONSTRAINT CK_BitacoraAcceso_Usuario CHECK (
            (Resultado = 'USUARIO_INEXISTENTE' AND UsuarioId IS NULL)
            OR (Resultado <> 'USUARIO_INEXISTENTE' AND UsuarioId IS NOT NULL)
        )
    );
    CREATE INDEX IX_BitacoraAcceso_Fecha ON dbo.Bitacora_Acceso(FechaHora);
    CREATE INDEX IX_BitacoraAcceso_Usuario ON dbo.Bitacora_Acceso(UsuarioId, FechaHora);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- =========================================================
-- Fuente: database/03_SecurityStoredProcedures.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- SQL Server 2016 SP1 o posterior (CREATE OR ALTER).
-- Contrato único: NVARCHAR, máximo 128 unidades UTF-16 (256 bytes), sin trim
-- ni normalización del password. Bytes UTF-16LE + Salt binario de 32 bytes.
-- Cualquier futuro cambio de password DEBE repetir esta fórmula con una sal nueva:
-- HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt).
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarUsuario
    @NombreUsuario NVARCHAR(MAX),
    @Correo NVARCHAR(MAX),
    @Password NVARCHAR(MAX),
    @NombreCompleto NVARCHAR(MAX),
    @UsuarioId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @UsuarioId = NULL;
    BEGIN TRY
        IF @NombreUsuario IS NULL OR DATALENGTH(@NombreUsuario) > 100
           OR LEN(LTRIM(RTRIM(@NombreUsuario))) = 0
           OR @Correo IS NULL OR DATALENGTH(@Correo) > 508
           OR LEN(LTRIM(RTRIM(@Correo))) = 0
           OR @NombreCompleto IS NULL OR DATALENGTH(@NombreCompleto) > 300
           OR LEN(LTRIM(RTRIM(@NombreCompleto))) = 0
           OR @Password IS NULL OR DATALENGTH(@Password) = 0 OR DATALENGTH(@Password) > 256
        BEGIN
            SELECT 10 AS Codigo, 'DATOS_INVALIDOS' AS Resultado, @UsuarioId AS UsuarioId;
            RETURN 10;
        END;
        -- Se respetan las restricciones y collation del modelo existente.
        IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE NombreUsuario = @NombreUsuario OR Correo = @Correo)
        BEGIN
            SELECT 11 AS Codigo, 'USUARIO_O_CORREO_EXISTENTE' AS Resultado, @UsuarioId AS UsuarioId;
            RETURN 11;
        END;
        DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
        DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt);
        -- Un solo INSERT es atómico; UNIQUE protege también carreras concurrentes.
        INSERT dbo.Usuario (NombreUsuario, NombreCompleto, Correo, PasswordHash, Salt)
        VALUES (@NombreUsuario, @NombreCompleto, @Correo, @Hash, @Salt);
        SET @UsuarioId = CONVERT(INT, SCOPE_IDENTITY());
        SELECT 0 AS Codigo, 'REGISTRADO' AS Resultado, @UsuarioId AS UsuarioId;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
        BEGIN
            -- Incluye una improbable colisión de sal: nunca insertar una sal repetida.
            SELECT 12 AS Codigo, 'CONFLICTO_UNICIDAD' AS Resultado, @UsuarioId AS UsuarioId;
            RETURN 12;
        END;
        THROW; -- Error técnico: no convertirlo en un registro exitoso.
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarAcceso
    @UsuarioId INT,
    @NombreUsuarioIntentado NVARCHAR(MAX),
    @Resultado VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    -- El esquema existente admite 50 caracteres; un nombre inválido más largo
    -- se conserva hasta ese límite. NULL se representa como cadena vacía.
    INSERT dbo.Bitacora_Acceso
        (UsuarioId, NombreUsuarioIntentado, Resultado, FechaHora,
         HostName, AppName, UsuarioSQL, IpConexionSQL)
    VALUES
        (@UsuarioId, CONVERT(NVARCHAR(50), COALESCE(@NombreUsuarioIntentado, N'')),
         @Resultado, SYSUTCDATETIME(), HOST_NAME(), APP_NAME(), SUSER_SNAME(),
         CONVERT(VARCHAR(48), CONNECTIONPROPERTY('client_net_address')));
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Login
    @NombreUsuario NVARCHAR(MAX),
    @Password NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @UsuarioId INT, @Nombre NVARCHAR(50), @Correo NVARCHAR(254),
            @Activo BIT, @DebeCambiarPassword BIT, @Salt VARBINARY(32),
            @Hash VARBINARY(64), @Calculado VARBINARY(64),
            @Codigo INT, @Resultado VARCHAR(30);
    SELECT @UsuarioId = UsuarioId, @Nombre = NombreUsuario, @Correo = Correo,
           @Activo = Activo, @DebeCambiarPassword = DebeCambiarPassword,
           @Salt = Salt, @Hash = PasswordHash
    FROM dbo.Usuario
    WHERE NombreUsuario = @NombreUsuario AND DATALENGTH(@NombreUsuario) <= 100;

    IF @UsuarioId IS NULL
        SELECT @Codigo = 1, @Resultado = 'USUARIO_INEXISTENTE';
    ELSE IF @Activo = 0
        SELECT @Codigo = 2, @Resultado = 'USUARIO_INACTIVO';
    ELSE
    BEGIN
        IF @Password IS NOT NULL AND DATALENGTH(@Password) BETWEEN 1 AND 256
            SET @Calculado = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt);
        IF @Calculado IS NOT NULL AND @Calculado = @Hash
            SELECT @Codigo = 0, @Resultado = 'EXITOSO';
        ELSE
            SELECT @Codigo = 3, @Resultado = 'PASSWORD_INCORRECTA';
    END;
    -- No devolver éxito si falla la auditoría. No se capturan errores técnicos.
    EXEC dbo.sp_RegistrarAcceso @UsuarioId, @NombreUsuario, @Resultado;
    SELECT @Codigo AS Codigo, @Resultado AS Resultado,
           CASE WHEN @Codigo = 0 THEN @UsuarioId END AS UsuarioId,
           CASE WHEN @Codigo = 0 THEN @Nombre END AS NombreUsuario,
           CASE WHEN @Codigo = 0 THEN @Correo END AS Correo,
           CASE WHEN @Codigo = 0 THEN @Activo END AS Activo,
           CASE WHEN @Codigo = 0 THEN @DebeCambiarPassword END AS DebeCambiarPassword;
    RETURN @Codigo;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPermisosUsuario
    @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Permisos efectivos únicos, incluso si varios roles conceden el mismo.
    SELECT DISTINCT p.PermisoId, p.Codigo
    FROM dbo.Usuario AS u
    INNER JOIN dbo.Usuario_Rol AS ur ON ur.UsuarioId = u.UsuarioId
    INNER JOIN dbo.Rol AS r ON r.RolId = ur.RolId AND r.Activo = 1
    INNER JOIN dbo.Rol_Permiso AS rp ON rp.RolId = r.RolId
    INNER JOIN dbo.Permiso AS p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1
    ORDER BY p.Codigo;
END;
GO

-- =========================================================
-- Fuente: database/04_SecuritySeedData.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- DEMO académica local. No ejecutar estas credenciales públicas en producción.
-- Reejecutar conserva las contraseñas y estados existentes.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Rol (Nombre, Descripcion)
    SELECT s.Nombre, s.Descripcion
    FROM (VALUES
        (N'Administrador', N'Administración académica del sistema'),
        (N'Cajero', N'Operaciones de caja'),
        (N'Auditor', N'Consulta de auditoría')
    ) AS s(Nombre, Descripcion)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK) WHERE Nombre = s.Nombre);

    INSERT dbo.Permiso (Codigo, Descripcion)
    SELECT s.Codigo, s.Descripcion
    FROM (VALUES
        (N'USUARIOS_ADMINISTRAR', N'Administrar usuarios y asignaciones'),
        (N'VENTAS_REGISTRAR', N'Registrar ventas en una fase posterior'),
        (N'AUDITORIA_CONSULTAR', N'Consultar auditoría')
    ) AS s(Codigo, Descripcion)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Permiso WITH (UPDLOCK, HOLDLOCK) WHERE Codigo = s.Codigo);

    INSERT dbo.Rol_Permiso (RolId, PermisoId)
    SELECT r.RolId, p.PermisoId
    FROM (VALUES
        (N'Administrador', N'USUARIOS_ADMINISTRAR'),
        (N'Administrador', N'VENTAS_REGISTRAR'),
        (N'Administrador', N'AUDITORIA_CONSULTAR'),
        (N'Cajero', N'VENTAS_REGISTRAR'),
        (N'Auditor', N'AUDITORIA_CONSULTAR')
    ) AS s(Rol, Permiso)
    JOIN dbo.Rol AS r ON r.Nombre = s.Rol
    JOIN dbo.Permiso AS p ON p.Codigo = s.Permiso
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Rol_Permiso WITH (UPDLOCK, HOLDLOCK)
                      WHERE RolId = r.RolId AND PermisoId = p.PermisoId);

    DECLARE @UsuarioId INT, @Codigo INT;
    SELECT @UsuarioId = UsuarioId FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK)
    WHERE NombreUsuario = N'admin';
    IF @UsuarioId IS NULL
    BEGIN
        EXEC @Codigo = dbo.sp_RegistrarUsuario
            @NombreUsuario = N'admin', @Correo = N'admin.demo@example.invalid',
            @Password = N'Demo_Academica_2026!', @NombreCompleto = N'Administrador DEMO',
            @UsuarioId = @UsuarioId OUTPUT;
        IF @Codigo <> 0 OR @UsuarioId IS NULL
            THROW 51100, 'No fue posible crear admin. Revisar conflictos de usuario/correo.', 1;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId
                        AND Correo = N'admin.demo@example.invalid' AND NombreCompleto = N'Administrador DEMO')
        THROW 51101, 'admin ya pertenece a otra identidad. No se asignaron privilegios.', 1;

    INSERT dbo.Usuario_Rol (UsuarioId, RolId)
    SELECT @UsuarioId, r.RolId FROM dbo.Rol AS r
    WHERE r.Nombre = N'Administrador'
      AND NOT EXISTS (SELECT 1 FROM dbo.Usuario_Rol WITH (UPDLOCK, HOLDLOCK)
                      WHERE UsuarioId = @UsuarioId AND RolId = r.RolId);
    COMMIT TRANSACTION;
    PRINT N'OK: semillas DEMO disponibles; datos existentes conservados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- =========================================================
-- Fuente: database/05_BusinessTables.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
-- Instalación inicial, una sola vez después de 01-04. No reemplaza objetos.
-- Fechas UTC; precios sin IVA. El ingreso de caja representa la venta cobrada.
BEGIN TRY
    BEGIN TRANSACTION;
    CREATE TABLE dbo.Cliente (
        ClienteId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
        NIT NVARCHAR(25) NOT NULL CONSTRAINT UQ_Cliente_NIT UNIQUE,
        Nombre NVARCHAR(150) NOT NULL,
        Correo NVARCHAR(254) NULL,
        Telefono NVARCHAR(25) NULL,
        Activo BIT NOT NULL CONSTRAINT DF_Cliente_Activo DEFAULT (1),
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Cliente_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Cliente_NIT CHECK (LEN(LTRIM(RTRIM(NIT))) > 0),
        CONSTRAINT CK_Cliente_Nombre CHECK (LEN(LTRIM(RTRIM(Nombre))) > 0)
    );
    CREATE TABLE dbo.Producto (
        ProductoId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Producto PRIMARY KEY,
        Codigo NVARCHAR(40) NOT NULL CONSTRAINT UQ_Producto_Codigo UNIQUE,
        Descripcion NVARCHAR(200) NOT NULL,
        Precio DECIMAL(12,2) NOT NULL,
        Stock INT NOT NULL CONSTRAINT DF_Producto_Stock DEFAULT (0),
        Activo BIT NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT (1),
        FechaCreacion DATETIME2(3) NOT NULL CONSTRAINT DF_Producto_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Producto_Codigo CHECK (LEN(LTRIM(RTRIM(Codigo))) > 0),
        CONSTRAINT CK_Producto_Descripcion CHECK (LEN(LTRIM(RTRIM(Descripcion))) > 0),
        CONSTRAINT CK_Producto_Precio CHECK (Precio >= 0),
        CONSTRAINT CK_Producto_Stock CHECK (Stock >= 0)
    );
    CREATE TABLE dbo.Factura (
        FacturaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Factura PRIMARY KEY,
        ClienteId INT NOT NULL CONSTRAINT FK_Factura_Cliente REFERENCES dbo.Cliente(ClienteId),
        UsuarioId INT NOT NULL CONSTRAINT FK_Factura_Usuario REFERENCES dbo.Usuario(UsuarioId),
        FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_Factura_Fecha DEFAULT SYSUTCDATETIME(),
        Subtotal DECIMAL(19,2) NOT NULL,
        DescuentoTotal DECIMAL(19,2) NOT NULL CONSTRAINT DF_Factura_DescuentoTotal DEFAULT (0),
        MotivoDescuento NVARCHAR(80) NULL,
        IVA DECIMAL(19,2) NOT NULL,
        Total DECIMAL(19,2) NOT NULL,
        Estado VARCHAR(15) NOT NULL CONSTRAINT DF_Factura_Estado DEFAULT ('EMITIDA'),
        CONSTRAINT CK_Factura_Importes CHECK (Subtotal >= 0 AND DescuentoTotal BETWEEN 0 AND Subtotal AND IVA >= 0 AND Total = Subtotal - DescuentoTotal + IVA),
        CONSTRAINT CK_Factura_Estado CHECK (Estado = 'EMITIDA'),
        CONSTRAINT CK_Factura_MotivoDescuento CHECK (MotivoDescuento IS NULL OR MotivoDescuento IN
            (N'Promoción', N'Cliente frecuente', N'Ajuste comercial', N'Autorización administrativa', N'Otro'))
    );
    CREATE INDEX IX_Factura_Cliente ON dbo.Factura(ClienteId, FechaHora);
    CREATE INDEX IX_Factura_Usuario ON dbo.Factura(UsuarioId);
    CREATE TABLE dbo.DetalleFactura (
        DetalleFacturaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DetalleFactura PRIMARY KEY,
        FacturaId INT NOT NULL CONSTRAINT FK_DetalleFactura_Factura REFERENCES dbo.Factura(FacturaId),
        ProductoId INT NOT NULL CONSTRAINT FK_DetalleFactura_Producto REFERENCES dbo.Producto(ProductoId),
        Cantidad INT NOT NULL,
        PrecioUnitario DECIMAL(12,2) NOT NULL,
        Subtotal DECIMAL(19,2) NOT NULL,
        DescuentoPorcentaje DECIMAL(5,2) NOT NULL CONSTRAINT DF_DetalleFactura_DescuentoPorcentaje DEFAULT (0),
        DescuentoMonto DECIMAL(19,2) NOT NULL CONSTRAINT DF_DetalleFactura_DescuentoMonto DEFAULT (0),
        SubtotalNeto AS (Subtotal - DescuentoMonto) PERSISTED,
        CONSTRAINT CK_DetalleFactura_Descuento CHECK (DescuentoPorcentaje BETWEEN 0 AND 100 AND DescuentoMonto BETWEEN 0 AND Subtotal AND DescuentoMonto = ROUND(Subtotal * DescuentoPorcentaje / CONVERT(DECIMAL(5,2), 100), 2)),
        CONSTRAINT UQ_DetalleFactura_Producto UNIQUE (FacturaId, ProductoId),
        CONSTRAINT CK_DetalleFactura_Cantidad CHECK (Cantidad > 0),
        CONSTRAINT CK_DetalleFactura_Precio CHECK (PrecioUnitario >= 0),
        CONSTRAINT CK_DetalleFactura_Subtotal CHECK (Subtotal >= 0 AND Subtotal = PrecioUnitario * CONVERT(DECIMAL(10,0), Cantidad))
    );
    CREATE INDEX IX_DetalleFactura_Producto ON dbo.DetalleFactura(ProductoId);
    CREATE TABLE dbo.MovimientoCaja (
        MovimientoCajaId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientoCaja PRIMARY KEY,
        FacturaId INT NOT NULL CONSTRAINT UQ_MovimientoCaja_Factura UNIQUE
            CONSTRAINT FK_MovimientoCaja_Factura REFERENCES dbo.Factura(FacturaId),
        TipoMovimiento VARCHAR(10) NOT NULL CONSTRAINT DF_MovimientoCaja_Tipo DEFAULT ('INGRESO'),
        Monto DECIMAL(19,2) NOT NULL,
        FechaHora DATETIME2(3) NOT NULL CONSTRAINT DF_MovimientoCaja_Fecha DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_MovimientoCaja_Tipo CHECK (TipoMovimiento = 'INGRESO'),
        CONSTRAINT CK_MovimientoCaja_Monto CHECK (Monto >= 0)
    );
    -- Sin PK/CHECK aquí: el SP devuelve errores de negocio precisos para duplicados/cantidades.
    CREATE TYPE dbo.TipoDetalleVenta AS TABLE (ProductoId INT NOT NULL, Cantidad INT NOT NULL);
    CREATE TYPE dbo.TipoDetalleVentaDescuento AS TABLE (ProductoId INT NOT NULL, Cantidad INT NOT NULL, DescuentoPorcentaje DECIMAL(5,2) NOT NULL DEFAULT (0));
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- =========================================================
-- Fuente: database/05_BusinessSeedData.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Ficticios. Reejecutar no repone stock ni cambia precios/estados existentes.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Cliente (NIT, Nombre, Correo, Telefono)
    SELECT s.NIT, s.Nombre, s.Correo, s.Telefono
    FROM (VALUES
        (N'DEMO-001', N'Comercial Aurora DEMO', N'aurora@example.invalid', N'5550-0101'),
        (N'DEMO-002', N'Librería Horizonte DEMO', N'horizonte@example.invalid', N'5550-0102'),
        (N'CF-DEMO', N'Consumidor final DEMO', NULL, NULL)
    ) s(NIT, Nombre, Correo, Telefono)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Cliente WITH (UPDLOCK, HOLDLOCK) WHERE NIT = s.NIT);
    INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock)
    SELECT s.Codigo, s.Descripcion, s.Precio, s.Stock
    FROM (VALUES
        (N'DEMO-TECLADO', N'Teclado USB', CONVERT(DECIMAL(12,2), 125.50), 50),
        (N'DEMO-MOUSE', N'Mouse óptico', CONVERT(DECIMAL(12,2), 75.25), 80),
        (N'DEMO-MONITOR', N'Monitor 24 pulgadas', CONVERT(DECIMAL(12,2), 1450.00), 20),
        (N'DEMO-CABLE', N'Cable HDMI', CONVERT(DECIMAL(12,2), 35.90), 100)
    ) s(Codigo, Descripcion, Precio, Stock)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE Codigo = s.Codigo);
    COMMIT TRANSACTION;
    PRINT N'OK: semillas de negocio disponibles; datos existentes conservados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- =========================================================
-- Fuente: database/06_TransactionProcedures.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Política compartida por la preparación y el COMMIT. Sin roles del navegador.
CREATE OR ALTER FUNCTION dbo.fn_ObtenerPoliticaVenta (@UsuarioId INT)
RETURNS TABLE
AS RETURN
    SELECT CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo = N'VENTAS_REGISTRAR' THEN 1 ELSE 0 END), 0)) AS PuedeVender,
        CONVERT(DECIMAL(5,2), CASE WHEN MAX(CASE WHEN r.Nombre = N'Administrador'
            AND p.Codigo = N'VENTAS_REGISTRAR' THEN 1 ELSE 0 END) = 1 THEN 100 ELSE 10 END) AS MaxDescuento
    FROM dbo.Usuario u WITH (HOLDLOCK)
    INNER JOIN dbo.Usuario_Rol ur WITH (HOLDLOCK) ON ur.UsuarioId = u.UsuarioId
    INNER JOIN dbo.Rol r WITH (HOLDLOCK) ON r.RolId = ur.RolId AND r.Activo = 1
    INNER JOIN dbo.Rol_Permiso rp WITH (HOLDLOCK) ON rp.RolId = r.RolId
    INNER JOIN dbo.Permiso p WITH (HOLDLOCK) ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPoliticaVenta @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1)
        THROW 52007, 'El usuario no existe o está inactivo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId) WHERE PuedeVender = 1)
        THROW 52013, 'No tienes permiso para registrar ventas.', 1;
    SELECT MaxDescuento FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarClientes
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ClienteId, NIT, Nombre FROM dbo.Cliente WHERE Activo = 1 ORDER BY Nombre, ClienteId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarProductosDisponibles
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ProductoId, Codigo, Descripcion, Precio, Stock
    FROM dbo.Producto WHERE Activo = 1 ORDER BY Descripcion, ProductoId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
    @ClienteId INT,
    @UsuarioId INT,
    @Detalle dbo.TipoDetalleVentaDescuento READONLY,
    @FacturaId INT = NULL OUTPUT,
    @MotivoDescuento NVARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @FacturaId = NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            THROW 52001, 'La venta debe contener productos.', 1;
        IF (SELECT COUNT_BIG(*) FROM @Detalle) > 100
            THROW 52002, 'La venta admite hasta 100 productos.', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE Cantidad <= 0 OR ProductoId <= 0)
            THROW 52003, 'Producto o cantidad inválidos.', 1;
        IF EXISTS (SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*) > 1)
            THROW 52004, 'No se permiten productos repetidos.', 1;

        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje IS NULL OR DescuentoPorcentaje < 0 OR DescuentoPorcentaje > 100)
            THROW 52011, 'El descuento debe estar entre 0.00 y 100.00.', 1;

        DECLARE @Activo BIT, @ClienteNombre NVARCHAR(150), @NIT NVARCHAR(25), @Cajero NVARCHAR(50);
        SELECT @Activo = Activo, @ClienteNombre = Nombre, @NIT = NIT
        FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, 'El cliente no existe.', 1;
        IF @Activo = 0 THROW 52006, 'El cliente está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, 'El usuario no existe o está inactivo.', 1;
        DECLARE @MaxDescuento DECIMAL(5,2), @PuedeVender BIT;
        SELECT @MaxDescuento = MaxDescuento, @PuedeVender = PuedeVender
        FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
        IF @PuedeVender = 0 THROW 52013, 'No tienes permiso para registrar ventas.', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > @MaxDescuento)
            THROW 52012, 'El descuento máximo autorizado para tu rol es 10%.', 1;
        SET @MotivoDescuento = NULLIF(LTRIM(RTRIM(@MotivoDescuento)), N'');
        IF @MotivoDescuento IS NOT NULL AND @MotivoDescuento NOT IN
            (N'Promoción', N'Cliente frecuente', N'Ajuste comercial', N'Autorización administrativa', N'Otro')
            THROW 52014, 'Selecciona un motivo de descuento válido.', 1;
        IF NOT EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > 0) SET @MotivoDescuento = NULL;
        SELECT @Cajero = NombreUsuario FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId;

        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2),
            DescuentoPorcentaje DECIMAL(5,2), DescuentoMonto DECIMAL(19,2), SubtotalNeto DECIMAL(19,2),
            Descripcion NVARCHAR(200));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT, @Porcentaje DECIMAL(5,2),
                @Bruto DECIMAL(19,2), @MontoDescuento DECIMAL(19,2), @Descripcion NVARCHAR(200);
        -- Acceso puntual por PK en orden ascendente, independiente del orden del TVP.
        -- UPDLOCK + HOLDLOCK conserva precio/stock hasta COMMIT y serializa ventas
        -- del mismo producto. No se reintentan ventas automáticamente tras un timeout.
        WHILE 1 = 1
        BEGIN
            SELECT @Siguiente = MIN(ProductoId) FROM @Detalle WHERE ProductoId > @ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId = @Siguiente;
            SELECT @Cantidad = Cantidad, @Porcentaje = DescuentoPorcentaje FROM @Detalle WHERE ProductoId = @ProductoId;
            SELECT @Precio = NULL, @Stock = NULL, @Activo = NULL;
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo, @Descripcion = Descripcion
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, 'Un producto no existe.', 1;
            IF @Activo = 0 THROW 52009, 'Un producto está inactivo.', 1;
            IF @Stock < @Cantidad THROW 52010, 'Stock insuficiente para uno de los productos.', 1;
            SET @Bruto = @Precio * CONVERT(DECIMAL(10,0), @Cantidad);
            SET @MontoDescuento = ROUND(@Bruto * @Porcentaje / CONVERT(DECIMAL(5,2), 100), 2);
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio, @Bruto,
                @Porcentaje, @MontoDescuento, @Bruto - @MontoDescuento, @Descripcion);
            UPDATE dbo.Producto SET Stock = Stock - @Cantidad WHERE ProductoId = @ProductoId;
        END;

        -- Descuento por línea e IVA sobre el neto global, redondeados a centavos.
        -- ROUND: mitades hacia arriba para importes no negativos; solo DECIMAL.
        DECLARE @Descuento DECIMAL(19,2), @SubtotalNeto DECIMAL(19,2),
                @Subtotal DECIMAL(19,2), @IVA DECIMAL(19,2), @Total DECIMAL(19,2),
                @FechaHora DATETIME2(3) = SYSUTCDATETIME();
        SELECT @Subtotal = SUM(Subtotal), @Descuento = SUM(DescuentoMonto),
            @SubtotalNeto = SUM(SubtotalNeto) FROM @Lineas;
        SET @IVA = ROUND(@SubtotalNeto * CONVERT(DECIMAL(3,2), 0.12), 2);
        SET @Total = @SubtotalNeto + @IVA;
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, DescuentoTotal, IVA, Total, MotivoDescuento)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @Descuento, @IVA, @Total, @MotivoDescuento);
        SET @FacturaId = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.DetalleFactura (FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto)
        SELECT @FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto FROM @Lineas;
        INSERT dbo.MovimientoCaja (FacturaId, Monto, FechaHora) VALUES (@FacturaId, @Total, @FechaHora);
        COMMIT TRANSACTION;
        -- Strings monetarios evitan pérdida de centavos al convertir DECIMAL(19,2) a JS Number.
        SELECT @FacturaId AS FacturaId, @FechaHora AS FechaHora,
            CONVERT(VARCHAR(21), @Subtotal) AS Subtotal,
            CONVERT(VARCHAR(21), @Descuento) AS Descuento,
            CONVERT(VARCHAR(21), @SubtotalNeto) AS SubtotalNeto,
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total,
            @ClienteNombre AS Cliente, @NIT AS NIT, @Cajero AS Cajero, @MotivoDescuento AS MotivoDescuento;
        SELECT ProductoId, Descripcion, Cantidad,
            CONVERT(VARCHAR(21), PrecioUnitario) AS PrecioUnitario,
            CONVERT(VARCHAR(21), Subtotal) AS Subtotal,
            CONVERT(VARCHAR(6), DescuentoPorcentaje) AS DescuentoPorcentaje,
            CONVERT(VARCHAR(21), DescuentoMonto) AS DescuentoMonto,
            CONVERT(VARCHAR(21), SubtotalNeto) AS SubtotalNeto
        FROM @Lineas ORDER BY ProductoId;
    END TRY
    BEGIN CATCH
        -- Sin SAVEPOINT: la venta debe revertirse completa. Si el llamador abrió
        -- una transacción, también se revierte; Node llama el SP en autocommit.
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @FacturaId = NULL;
        THROW;
    END CATCH;
END;
GO

-- Adaptador para integraciones que conservan el TVP anterior.
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaSinDescuento
    @ClienteId INT, @UsuarioId INT, @Detalle dbo.TipoDetalleVenta READONLY,
    @FacturaId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Nuevo dbo.TipoDetalleVentaDescuento;
    INSERT @Nuevo (ProductoId, Cantidad, DescuentoPorcentaje)
    SELECT ProductoId, Cantidad, 0 FROM @Detalle;
    EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId, @UsuarioId, @Nuevo, @FacturaId OUTPUT;
END;
GO

-- =========================================================
-- Fuente: database/07_AuditCore.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Bitacora_Transacciones', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bitacora_Transacciones (
        BitacoraTransaccionId BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Bitacora_Transacciones PRIMARY KEY,
        FechaHora DATETIME2(3) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_Fecha DEFAULT SYSUTCDATETIME(),
        TablaAfectada NVARCHAR(128) NOT NULL
            CONSTRAINT CK_BitacoraTransacciones_Tabla CHECK (LEN(LTRIM(RTRIM(TablaAfectada)) ) > 0),
        Operacion VARCHAR(20) NOT NULL
            CONSTRAINT CK_BitacoraTransacciones_Operacion CHECK (Operacion IN ('INSERT', 'UPDATE', 'DELETE')),
        UsuarioSQL NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_UsuarioSQL DEFAULT SUSER_SNAME(),
        HostName NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_Host DEFAULT HOST_NAME(),
        AppName NVARCHAR(128) NOT NULL
            CONSTRAINT DF_BitacoraTransacciones_App DEFAULT APP_NAME(),
        IdentificadorRegistro NVARCHAR(4000) NOT NULL,
        ValorAnterior NVARCHAR(MAX) NULL,
        ValorNuevo NVARCHAR(MAX) NULL,
        CONSTRAINT CK_BitacoraTransacciones_Registro CHECK (LEN(LTRIM(RTRIM(IdentificadorRegistro))) > 0)
    );

    CREATE INDEX IX_BitacoraTransacciones_Fecha ON dbo.Bitacora_Transacciones(FechaHora);
    CREATE INDEX IX_BitacoraTransacciones_Tabla ON dbo.Bitacora_Transacciones(TablaAfectada, FechaHora);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularIVA
(
    @Monto DECIMAL(18, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN CAST(@Monto * 0.12 AS DECIMAL(18,2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_CalcularSubtotal
(
    @Cantidad DECIMAL(18, 2),
    @PrecioUnitario DECIMAL(18, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN CAST(@Cantidad * @PrecioUnitario AS DECIMAL(18, 2));
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_ConsultarAuditoria
(
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Tabla NVARCHAR(128) = NULL,
    @Operacion VARCHAR(20) = NULL
)
RETURNS TABLE
AS
RETURN
    SELECT
        bt.BitacoraTransaccionId,
        bt.FechaHora,
        bt.TablaAfectada,
        bt.Operacion,
        bt.UsuarioSQL,
        bt.HostName,
        bt.AppName,
        bt.IdentificadorRegistro,
        bt.ValorAnterior,
        bt.ValorNuevo
    FROM dbo.Bitacora_Transacciones AS bt
    WHERE (@FechaInicial IS NULL OR bt.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR bt.FechaHora <= @FechaFinal)
      AND (@Tabla IS NULL OR bt.TablaAfectada = @Tabla)
      AND (@Operacion IS NULL OR bt.Operacion = @Operacion);
GO

CREATE OR ALTER FUNCTION dbo.fn_ObtenerHistoricoVentas
(
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
)
RETURNS TABLE
AS
RETURN
    SELECT f.FacturaId AS Factura, f.FechaHora AS Fecha,
           c.Nombre AS Cliente, u.NombreUsuario AS Usuario,
           f.Subtotal, f.IVA, f.Total, f.DescuentoTotal AS Descuento,
           f.Subtotal - f.DescuentoTotal AS SubtotalNeto
    FROM dbo.Factura AS f
    INNER JOIN dbo.Cliente AS c ON c.ClienteId = f.ClienteId
    INNER JOIN dbo.Usuario AS u ON u.UsuarioId = f.UsuarioId
    WHERE (@FechaInicial IS NULL OR f.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR f.FechaHora <= @FechaFinal)
      AND (@Cliente IS NULL OR CHARINDEX(@Cliente, c.Nombre) > 0);
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistoricoVentas
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Factura, Fecha, Cliente, Usuario, Subtotal, IVA, Total, Descuento, SubtotalNeto
    FROM dbo.fn_ObtenerHistoricoVentas(@FechaInicial, @FechaFinal, @Cliente)
    ORDER BY Fecha DESC, Factura DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarBitacoraAcceso
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @NombreUsuarioIntentado NVARCHAR(50) = NULL,
    @Resultado VARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        ba.FechaHora,
        ba.NombreUsuarioIntentado,
        ba.Resultado,
        ba.HostName,
        ba.AppName,
        ba.UsuarioSQL,
        ba.IpConexionSQL
    FROM dbo.Bitacora_Acceso AS ba
    WHERE (@FechaInicial IS NULL OR ba.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR ba.FechaHora <= @FechaFinal)
      AND (@NombreUsuarioIntentado IS NULL OR ba.NombreUsuarioIntentado = @NombreUsuarioIntentado)
      AND (@Resultado IS NULL OR ba.Resultado = @Resultado)
    ORDER BY ba.FechaHora DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarAuditoriaTransacciones
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Tabla NVARCHAR(128) = NULL,
    @Operacion VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM dbo.fn_ConsultarAuditoria(@FechaInicial, @FechaFinal, @Tabla, @Operacion)
    ORDER BY FechaHora DESC;
END;
GO

-- =========================================================
-- Fuente: database/08_AuditTriggers.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
GO
-- La autenticacion se registra exclusivamente en Bitacora_Acceso.
DROP TRIGGER IF EXISTS dbo.tr_Usuario_Auditar_Update;
GO

CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Update
ON dbo.Producto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Producto', 'UPDATE', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.ProductoId),
           (SELECT d.ProductoId, d.Codigo, d.Descripcion, d.Precio, d.Stock, d.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.ProductoId, i.Codigo, i.Descripcion, i.Precio, i.Stock, i.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i INNER JOIN deleted AS d ON d.ProductoId = i.ProductoId
    WHERE d.Precio <> i.Precio OR d.Stock <> i.Stock;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_Producto_Auditar_Delete
ON dbo.Producto
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Producto', 'DELETE', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), d.ProductoId),
           (SELECT d.ProductoId, d.Codigo, d.Descripcion, d.Precio, d.Stock, d.Activo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           NULL
    FROM deleted AS d;
END;
GO

CREATE OR ALTER TRIGGER dbo.tr_Factura_Auditar_Insert
ON dbo.Factura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N'Factura', 'INSERT', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.FacturaId),
           NULL,
           (SELECT i.FacturaId, i.ClienteId, i.UsuarioId, i.FechaHora, i.Subtotal, i.DescuentoTotal, i.MotivoDescuento, i.IVA, i.Total, i.Estado FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i;
END;
GO

-- =========================================================
-- Fuente: database/11_UserAdministration.sql
-- =========================================================
USE [SecureFinanceERP];
GO
IF TYPE_ID(N'dbo.TipoRolUsuario') IS NULL
    EXEC(N'CREATE TYPE dbo.TipoRolUsuario AS TABLE (RolId INT NOT NULL);');
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarUsuariosAdministracion
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.UsuarioId, u.NombreUsuario, u.NombreCompleto, u.Correo, u.Activo,
           (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), r.Nombre), N', ') WITHIN GROUP (ORDER BY r.Nombre)
            FROM dbo.Usuario_Rol ur INNER JOIN dbo.Rol r ON r.RolId = ur.RolId
            WHERE ur.UsuarioId = u.UsuarioId AND r.Activo = 1) AS Roles
    FROM dbo.Usuario u ORDER BY u.NombreUsuario;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarRolesActivos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RolId, Nombre, Descripcion FROM dbo.Rol WHERE Activo = 1 ORDER BY Nombre;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerRolesUsuario @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId)
        THROW 53001, N'El usuario no existe.', 1;
    SELECT r.RolId, r.Nombre, r.Descripcion
    FROM dbo.Usuario_Rol ur INNER JOIN dbo.Rol r ON r.RolId = ur.RolId
    WHERE ur.UsuarioId = @UsuarioId AND r.Activo = 1 ORDER BY r.Nombre;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarRolesUsuario
    @UsuarioId INT, @Roles dbo.TipoRolUsuario READONLY, @ActorUsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        -- Serializa todas las modificaciones del módulo, incluida la comprobación del último administrador.
        DECLARE @LockResult INT;
        EXEC @LockResult = sys.sp_getapplock @Resource = N'SecureFinanceERP.UsuarioRoles',
            @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @LockResult < 0 THROW 53005, N'No fue posible obtener el bloqueo de administración.', 1;
        IF NOT EXISTS (
            SELECT 1 FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Usuario_Rol ur WITH (UPDLOCK, HOLDLOCK) ON ur.UsuarioId = u.UsuarioId
            INNER JOIN dbo.Rol r WITH (UPDLOCK, HOLDLOCK) ON r.RolId = ur.RolId AND r.Activo = 1
            INNER JOIN dbo.Rol_Permiso rp ON rp.RolId = r.RolId
            INNER JOIN dbo.Permiso p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
            WHERE u.UsuarioId = @ActorUsuarioId AND u.Activo = 1 AND p.Codigo = N'USUARIOS_ADMINISTRAR'
        ) THROW 53004, N'No tienes permiso para administrar usuarios.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK) WHERE UsuarioId = @UsuarioId)
            THROW 53001, N'El usuario no existe.', 1;
        IF EXISTS (SELECT RolId FROM @Roles GROUP BY RolId HAVING COUNT(*) > 1)
            OR EXISTS (SELECT 1 FROM @Roles t LEFT JOIN dbo.Rol r WITH (UPDLOCK, HOLDLOCK)
                       ON r.RolId = t.RolId AND r.Activo = 1 WHERE r.RolId IS NULL OR t.RolId <= 0)
            THROW 53002, N'Los roles deben ser únicos, existir y estar activos.', 1;
        DECLARE @Administrador INT = (SELECT RolId FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK)
                                      WHERE Nombre = N'Administrador' AND Activo = 1);
        IF EXISTS (SELECT 1 FROM dbo.Usuario_Rol WITH (UPDLOCK, HOLDLOCK)
                   WHERE UsuarioId = @UsuarioId AND RolId = @Administrador)
           AND EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1)
           AND NOT EXISTS (SELECT 1 FROM @Roles WHERE RolId = @Administrador)
           AND NOT EXISTS (SELECT 1 FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
                           INNER JOIN dbo.Usuario_Rol ur WITH (UPDLOCK, HOLDLOCK) ON ur.UsuarioId = u.UsuarioId
                           WHERE u.Activo = 1 AND u.UsuarioId <> @UsuarioId AND ur.RolId = @Administrador)
            THROW 53003, N'No se puede quitar el rol Administrador al último administrador activo.', 1;
        DECLARE @Anterior NVARCHAR(MAX) = (SELECT RolId FROM dbo.Usuario_Rol WHERE UsuarioId = @UsuarioId ORDER BY RolId FOR JSON PATH);
        -- Conserva asignaciones de roles inactivos: no están disponibles para editar en este módulo.
        DELETE ur FROM dbo.Usuario_Rol ur INNER JOIN dbo.Rol r ON r.RolId = ur.RolId
        WHERE ur.UsuarioId = @UsuarioId AND r.Activo = 1
          AND NOT EXISTS (SELECT 1 FROM @Roles t WHERE t.RolId = ur.RolId);
        INSERT dbo.Usuario_Rol (UsuarioId, RolId)
        SELECT @UsuarioId, t.RolId FROM @Roles t
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Usuario_Rol ur WHERE ur.UsuarioId = @UsuarioId AND ur.RolId = t.RolId);
        DECLARE @Nuevo NVARCHAR(MAX) = (SELECT RolId FROM dbo.Usuario_Rol WHERE UsuarioId = @UsuarioId ORDER BY RolId FOR JSON PATH);
        IF @Anterior <> @Nuevo
            INSERT dbo.Bitacora_Transacciones (TablaAfectada, Operacion, IdentificadorRegistro, ValorAnterior, ValorNuevo)
            VALUES (N'Usuario_Rol', 'UPDATE', CONCAT(N'UsuarioId=', @UsuarioId, N'; ActorUsuarioId=', @ActorUsuarioId), @Anterior, @Nuevo);
        COMMIT TRANSACTION;
        SELECT @UsuarioId AS UsuarioId, N'Roles actualizados correctamente.' AS Mensaje;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- =========================================================
-- Fuente: database/12_PasswordRecovery.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Migración repetible: reutiliza Usuario y Token_Recuperacion, sin cambiar el login.
-- Contraseñas NVARCHAR: 8..128 unidades UTF-16, sin normalización ni truncamiento.
CREATE OR ALTER PROCEDURE dbo.sp_SolicitarRecuperacionPassword
    @UsuarioOCorreo NVARCHAR(MAX), @TokenHash VARBINARY(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @UsuarioOCorreo IS NULL OR DATALENGTH(@UsuarioOCorreo) NOT BETWEEN 2 AND 508
       OR @TokenHash IS NULL OR DATALENGTH(@TokenHash) <> 64
    BEGIN
        SELECT CAST(0 AS BIT) AS Generado;
        RETURN;
    END;
    DECLARE @UsuarioId INT;
    -- Una coincidencia ambigua entre nombre/correo nunca selecciona otra cuenta.
    IF (SELECT COUNT(*) FROM dbo.Usuario WHERE Activo = 1
        AND (NombreUsuario = @UsuarioOCorreo OR Correo = @UsuarioOCorreo)) = 1
        SELECT @UsuarioId = UsuarioId FROM dbo.Usuario WHERE Activo = 1
          AND (NombreUsuario = @UsuarioOCorreo OR Correo = @UsuarioOCorreo);
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK)
                       WHERE UsuarioId = @UsuarioId AND Activo = 1)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST(0 AS BIT) AS Generado;
            RETURN;
        END;
        UPDATE dbo.Token_Recuperacion SET Invalidado = 1
        WHERE UsuarioId = @UsuarioId AND Invalidado = 0 AND FechaUso IS NULL;
        DECLARE @Ahora DATETIME2(3) = SYSUTCDATETIME();
        INSERT dbo.Token_Recuperacion (UsuarioId, TokenHash, FechaCreacion, FechaExpiracion)
        VALUES (@UsuarioId, @TokenHash, @Ahora, DATEADD(MINUTE, 15, @Ahora));
        COMMIT TRANSACTION;
        -- Solo el backend conoce este resultado; producción nunca lo publica.
        SELECT CAST(1 AS BIT) AS Generado;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ValidarTokenRecuperacion @TokenHash VARBINARY(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(CASE WHEN DATALENGTH(@TokenHash) = 64 AND EXISTS (
        SELECT 1 FROM dbo.Token_Recuperacion t INNER JOIN dbo.Usuario u ON u.UsuarioId = t.UsuarioId
        WHERE t.TokenHash = @TokenHash AND u.Activo = 1 AND t.Invalidado = 0
          AND t.FechaUso IS NULL AND t.FechaExpiracion > SYSUTCDATETIME()
    ) THEN 1 ELSE 0 END AS BIT) AS Valido;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_RestablecerPassword
    @TokenHash VARBINARY(MAX), @Password NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Password IS NULL OR DATALENGTH(@Password) NOT BETWEEN 16 AND 256
       OR LEN(LTRIM(RTRIM(@Password))) = 0
        THROW 54002, N'La contraseña debe tener entre 8 y 128 caracteres.', 1;
    IF @TokenHash IS NULL OR DATALENGTH(@TokenHash) <> 64
        THROW 54001, N'El enlace de recuperación no es válido o ha expirado.', 1;
    DECLARE @UsuarioId INT = (SELECT UsuarioId FROM dbo.Token_Recuperacion WHERE TokenHash = @TokenHash);
    BEGIN TRY
        BEGIN TRANSACTION;
        -- Todos los escritores bloquean primero Usuario y después sus tokens.
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK)
                       WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 54001, N'El enlace de recuperación no es válido o ha expirado.', 1;
        DECLARE @Ahora DATETIME2(3) = SYSUTCDATETIME();
        IF NOT EXISTS (SELECT 1 FROM dbo.Token_Recuperacion WITH (UPDLOCK, HOLDLOCK)
                       WHERE TokenHash = @TokenHash AND UsuarioId = @UsuarioId
                         AND Invalidado = 0 AND FechaUso IS NULL AND FechaExpiracion > @Ahora)
            THROW 54001, N'El enlace de recuperación no es válido o ha expirado.', 1;
        DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
        UPDATE dbo.Usuario
        SET Salt = @Salt,
            PasswordHash = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt),
            FechaCambioPassword = @Ahora, DebeCambiarPassword = 0
        WHERE UsuarioId = @UsuarioId;
        UPDATE dbo.Token_Recuperacion SET FechaUso = @Ahora, Invalidado = 1 WHERE TokenHash = @TokenHash;
        UPDATE dbo.Token_Recuperacion SET Invalidado = 1
        WHERE UsuarioId = @UsuarioId AND Invalidado = 0;
        COMMIT TRANSACTION;
        SELECT CAST(1 AS BIT) AS Actualizado;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_CambiarPassword
    @UsuarioId INT, @PasswordActual NVARCHAR(MAX), @Password NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Password IS NULL OR DATALENGTH(@Password) NOT BETWEEN 16 AND 256
       OR LEN(LTRIM(RTRIM(@Password))) = 0
        THROW 54002, N'La contraseña debe tener entre 8 y 128 caracteres.', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @SaltAnterior VARBINARY(32), @HashAnterior VARBINARY(64);
        SELECT @SaltAnterior = Salt, @HashAnterior = PasswordHash
        FROM dbo.Usuario WITH (UPDLOCK, HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1;
        IF @HashAnterior IS NULL OR @PasswordActual IS NULL
           OR DATALENGTH(@PasswordActual) NOT BETWEEN 1 AND 256
           OR HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @PasswordActual) + @SaltAnterior) <> @HashAnterior
            THROW 54003, N'La contraseña actual no es correcta.', 1;
        DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
        UPDATE dbo.Usuario
        SET Salt = @Salt,
            PasswordHash = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt),
            FechaCambioPassword = SYSUTCDATETIME(), DebeCambiarPassword = 0
        WHERE UsuarioId = @UsuarioId;
        UPDATE dbo.Token_Recuperacion SET Invalidado = 1 WHERE UsuarioId = @UsuarioId AND Invalidado = 0;
        COMMIT TRANSACTION;
        SELECT CAST(1 AS BIT) AS Actualizado;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- =========================================================
-- Fuente: database/14_DashboardSummary.sql
-- =========================================================
-- Migration and new-install module. Read-only summary; repeatable and atomic.
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ObtenerResumenDashboard @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1)
        THROW 52701, ''El usuario no existe o está inactivo.'', 1;
    -- Guatemala: UTC-6 sin cambio estacional. Las fechas persistidas siguen en UTC.
    DECLARE @Dia DATE = CONVERT(DATE, DATEADD(HOUR, -6, SYSUTCDATETIME()));
    DECLARE @Desde DATETIME2(3) = DATEADD(HOUR, 6, CONVERT(DATETIME2(3), @Dia)),
        @Hasta DATETIME2(3), @Ventas BIT = 0, @Auditoria BIT = 0;
    SET @Hasta = DATEADD(DAY, 1, @Desde);
    SELECT @Ventas = CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo IN
        (N''VENTAS_REGISTRAR'', N''AUDITORIA_CONSULTAR'') THEN 1 ELSE 0 END), 0)),
        @Auditoria = CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo = N''AUDITORIA_CONSULTAR'' THEN 1 ELSE 0 END), 0))
    FROM dbo.Usuario_Rol ur
    INNER JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
    INNER JOIN dbo.Rol_Permiso rp ON rp.RolId = r.RolId
    INNER JOIN dbo.Permiso p ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE ur.UsuarioId = @UsuarioId;
    SELECT
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(40),
            (SELECT COALESCE(SUM(Total), CONVERT(DECIMAL(38,2), 0)) FROM dbo.Factura
             WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS VentasDia,
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Factura WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS FacturasDia,
        CASE WHEN @Ventas = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Producto WHERE Activo = 1 AND Stock <= 5)) END AS ProductosStockBajo,
        CASE WHEN @Auditoria = 1 THEN CONVERT(VARCHAR(20),
            (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones WHERE FechaHora >= @Desde AND FechaHora < @Hasta)) END AS EventosDMLDia,
        CONVERT(VARCHAR(10), @Dia, 23) AS FechaOperacion,
        (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), r.Nombre), N'', '') WITHIN GROUP (ORDER BY r.Nombre)
         FROM dbo.Usuario_Rol ur INNER JOIN dbo.Rol r ON r.RolId = ur.RolId AND r.Activo = 1
         WHERE ur.UsuarioId = @UsuarioId) AS RolesActuales;
END;';
    IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NOT NULL
        GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerResumenDashboard TO [securefinance_app];
    COMMIT TRANSACTION;
    PRINT N'OK: Dashboard summary installed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- =========================================================
-- Fuente: database/10_AppPermissions.sql
-- =========================================================
-- Referencia final de permisos mínimos. Ejecutar después de instalar todos los módulos.
-- Usar una cuenta administradora con visibilidad del login y permisos para crear usuarios/conceder permisos.
-- No crea logins de servidor ni contraseñas. Puede volver a ejecutarse.
USE [SecureFinanceERP];
GO
IF SUSER_ID(N'securefinance_app') IS NULL
BEGIN
    PRINT N'ADVERTENCIA: la base SecureFinanceERP fue instalada; los permisos de aplicación quedan pendientes porque no existe el login de servidor securefinance_app.';
    PRINT N'El administrador debe crear/configurar manualmente el login y después ejecutar database/10_AppPermissions.sql.';
END
ELSE
BEGIN
    IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL
    BEGIN
        CREATE USER [securefinance_app] FOR LOGIN [securefinance_app];
    END;

    -- Autenticación: los procedimientos internos se ejecutan por la cadena de propiedad dbo.
    GRANT EXECUTE ON OBJECT::dbo.sp_Login TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerResumenDashboard TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPermisosUsuario TO [securefinance_app];
    -- Recuperación y cambio de contraseña: sin acceso directo a credenciales ni tokens.
    GRANT EXECUTE ON OBJECT::dbo.sp_SolicitarRecuperacionPassword TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ValidarTokenRecuperacion TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_RestablecerPassword TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_CambiarPassword TO [securefinance_app];

    -- Ventas y parámetro de tabla (TVP).
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPoliticaVenta TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductosDisponibles TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO [securefinance_app];
    GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVenta TO [securefinance_app];
    GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVentaDescuento TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaSinDescuento TO [securefinance_app];

    -- Usuarios y roles: procedimientos y TVP, sin acceso directo a tablas.
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarUsuariosAdministracion TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarRolesActivos TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerRolesUsuario TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarRolesUsuario TO [securefinance_app];
    GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoRolUsuario TO [securefinance_app];

    -- Consultas de auditoría e histórico de ventas.
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaTransacciones TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarHistoricoVentas TO [securefinance_app];

    PRINT N'OK: permisos mínimos de autenticación, ventas, TVP y auditoría aplicados a securefinance_app.';
END;
GO
