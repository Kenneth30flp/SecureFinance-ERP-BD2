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
