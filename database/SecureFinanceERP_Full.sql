-- Instalación NUEVA exclusivamente. No ejecutar sobre las tablas de Fase 1 existentes.
-- Copia unificada de 01, 02, 03 y 04. Sin módulos de negocio.

-- Fuente: database/01_CreateDatabase.sql
-- Ejecutar en SSMS con una cuenta autorizada para crear bases de datos.
USE [master];
GO
IF DB_ID(N'SecureFinanceERP') IS NULL
BEGIN
    CREATE DATABASE [SecureFinanceERP];
END;
GO


-- Fuente: database/02_SecurityTables.sql
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


-- Fuente: database/03_SecurityStoredProcedures.sql
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


-- Fuente: database/04_SecuritySeedData.sql
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

