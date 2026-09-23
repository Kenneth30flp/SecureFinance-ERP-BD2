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
