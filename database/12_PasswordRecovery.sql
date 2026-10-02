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
