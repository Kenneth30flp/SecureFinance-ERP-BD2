-- Instalación NUEVA de SecureFinance ERP.
-- Incluye seguridad, RBAC, negocio, ventas, auditoría y semillas DEMO.
-- No es una migración. No ejecutar sobre una instalación existente con las tablas ya creadas.
-- No crea passwords ni logins de servidor. El login securefinance_app se configura externamente.
-- Las fechas se almacenan en UTC donde aplica.
-- Las credenciales DEMO son exclusivamente académicas.
-- Ejecutar con una cuenta administradora en SSMS o sqlcmd; detener la ejecución ante errores.
-- Copia íntegra de los scripts modulares indicados en cada bloque, sin archivos de pruebas.

-- =========================================================
-- 01. CREACIÓN DE BASE DE DATOS
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
-- 02. SEGURIDAD, USUARIOS, ROLES Y PERMISOS
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
-- 03. PROCEDIMIENTOS DE AUTENTICACIÓN
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
-- 04. SEMILLAS DE SEGURIDAD
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
    WHERE NombreUsuario = N'admin_demo';
    IF @UsuarioId IS NULL
    BEGIN
        EXEC @Codigo = dbo.sp_RegistrarUsuario
            @NombreUsuario = N'admin_demo', @Correo = N'admin.demo@example.invalid',
            @Password = N'Demo_Academica_2026!', @NombreCompleto = N'Administrador DEMO',
            @UsuarioId = @UsuarioId OUTPUT;
        IF @Codigo <> 0 OR @UsuarioId IS NULL
            THROW 51100, 'No fue posible crear admin_demo. Revisar conflictos de usuario/correo.', 1;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId
                        AND Correo = N'admin.demo@example.invalid' AND NombreCompleto = N'Administrador DEMO')
        THROW 51101, 'admin_demo ya pertenece a otra identidad. No se asignaron privilegios.', 1;

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
-- 05. TABLAS DE NEGOCIO Y TVP
-- Fuente: database/05_BusinessTables.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET XACT_ABORT ON;
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
        IVA DECIMAL(19,2) NOT NULL,
        Total DECIMAL(19,2) NOT NULL,
        Estado VARCHAR(15) NOT NULL CONSTRAINT DF_Factura_Estado DEFAULT ('EMITIDA'),
        CONSTRAINT CK_Factura_Importes CHECK (Subtotal >= 0 AND IVA >= 0 AND Total = Subtotal + IVA),
        CONSTRAINT CK_Factura_Estado CHECK (Estado = 'EMITIDA')
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
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO


-- =========================================================
-- 06. SEMILLAS DE NEGOCIO
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
-- 07. PROCEDIMIENTOS TRANSACCIONALES
-- Fuente: database/06_TransactionProcedures.sql
-- =========================================================
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
    @Detalle dbo.TipoDetalleVenta READONLY,
    @FacturaId INT = NULL OUTPUT
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

        DECLARE @Activo BIT;
        SELECT @Activo = Activo FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, 'El cliente no existe.', 1;
        IF @Activo = 0 THROW 52006, 'El cliente está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, 'El usuario no existe o está inactivo.', 1;

        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT;
        -- Acceso puntual por PK en orden ascendente, independiente del orden del TVP.
        -- UPDLOCK + HOLDLOCK conserva precio/stock hasta COMMIT y serializa ventas
        -- del mismo producto. No se reintentan ventas automáticamente tras un timeout.
        WHILE 1 = 1
        BEGIN
            SELECT @Siguiente = MIN(ProductoId) FROM @Detalle WHERE ProductoId > @ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId = @Siguiente;
            SELECT @Cantidad = Cantidad FROM @Detalle WHERE ProductoId = @ProductoId;
            SELECT @Precio = NULL, @Stock = NULL, @Activo = NULL;
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, 'Un producto no existe.', 1;
            IF @Activo = 0 THROW 52009, 'Un producto está inactivo.', 1;
            IF @Stock < @Cantidad THROW 52010, 'Stock insuficiente para uno de los productos.', 1;
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio,
                @Precio * CONVERT(DECIMAL(10,0), @Cantidad));
            UPDATE dbo.Producto SET Stock = Stock - @Cantidad WHERE ProductoId = @ProductoId;
        END;

        -- Punto de integración futuro con las funciones de José. Redondeo del IVA
        -- sobre el subtotal global, a dos decimales; nunca FLOAT ni importes del cliente.
        DECLARE @Subtotal DECIMAL(19,2), @IVA DECIMAL(19,2), @Total DECIMAL(19,2),
                @FechaHora DATETIME2(3) = SYSUTCDATETIME();
        SELECT @Subtotal = SUM(Subtotal) FROM @Lineas;
        SET @IVA = ROUND(@Subtotal * CONVERT(DECIMAL(3,2), 0.12), 2);
        SET @Total = @Subtotal + @IVA;
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, IVA, Total)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @IVA, @Total);
        SET @FacturaId = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.DetalleFactura (FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal)
        SELECT @FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal FROM @Lineas;
        INSERT dbo.MovimientoCaja (FacturaId, Monto, FechaHora) VALUES (@FacturaId, @Total, @FechaHora);
        COMMIT TRANSACTION;
        -- Strings monetarios evitan pérdida de centavos al convertir DECIMAL(19,2) a JS Number.
        SELECT @FacturaId AS FacturaId, @FechaHora AS FechaHora,
            CONVERT(VARCHAR(21), @Subtotal) AS Subtotal,
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total;
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


-- =========================================================
-- 08. AUDITORÍA, FUNCIONES Y PROCEDIMIENTOS DE CONSULTA
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
           f.Subtotal, f.IVA, f.Total
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
    SELECT Factura, Fecha, Cliente, Usuario, Subtotal, IVA, Total
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
-- 09. TRIGGERS DE AUDITORÍA
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
           (SELECT i.FacturaId, i.ClienteId, i.UsuarioId, i.FechaHora, i.Subtotal, i.IVA, i.Total, i.Estado FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i;
END;
GO


-- =========================================================
-- 10. PERMISOS MÍNIMOS DE APLICACIÓN
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
    GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPermisosUsuario TO [securefinance_app];

    -- Ventas y parámetro de tabla (TVP).
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductosDisponibles TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO [securefinance_app];
    GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVenta TO [securefinance_app];

    -- Consultas de auditoría e histórico de ventas.
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaTransacciones TO [securefinance_app];
    GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarHistoricoVentas TO [securefinance_app];

    PRINT N'OK: permisos mínimos de autenticación, ventas, TVP y auditoría aplicados a securefinance_app.';
END;
GO
