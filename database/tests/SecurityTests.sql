USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
-- Datos temporales: la transacción se revierte incluso cuando las pruebas pasan.
-- Ejecutar con cuenta de desarrollo, nunca otorgar DML a la cuenta de aplicación.
SET XACT_ABORT OFF;
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Etiqueta NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
    DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
    DECLARE @Password NVARCHAR(128) = N'Prueba temporal del modelo';
    -- Convención binaria para futuros SP: UTF-16LE de NVARCHAR seguido de la sal.
    DECLARE @Hash VARBINARY(64) = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt);
    IF DATALENGTH(@Hash) <> 64 OR DATALENGTH(@Salt) <> 32
        THROW 51000, 'Longitudes de hash o sal incorrectas.', 1;

    INSERT dbo.Usuario (NombreUsuario, NombreCompleto, Correo, PasswordHash, Salt)
    VALUES (@Etiqueta, N'Usuario temporal', @Etiqueta + N'@example.invalid', @Hash, @Salt);
    DECLARE @UsuarioId INT = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Rol (Nombre) VALUES (@Etiqueta);
    DECLARE @RolId INT = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Permiso (Codigo) VALUES (@Etiqueta);
    DECLARE @PermisoId INT = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Usuario_Rol (UsuarioId, RolId) VALUES (@UsuarioId, @RolId);
    INSERT dbo.Rol_Permiso (RolId, PermisoId) VALUES (@RolId, @PermisoId);
    INSERT dbo.Token_Recuperacion (UsuarioId, TokenHash, FechaExpiracion)
    VALUES (@UsuarioId, HASHBYTES('SHA2_512', CRYPT_GEN_RANDOM(32)), DATEADD(MINUTE, 15, SYSUTCDATETIME()));
    INSERT dbo.Bitacora_Acceso (UsuarioId, NombreUsuarioIntentado, Resultado)
    VALUES (@UsuarioId, @Etiqueta, 'EXITOSO'),
           (@UsuarioId, @Etiqueta, 'PASSWORD_INCORRECTA'),
           (@UsuarioId, @Etiqueta, 'USUARIO_INACTIVO'),
           (NULL, @Etiqueta + N'_no_existe', 'USUARIO_INEXISTENTE');

    BEGIN TRY
        INSERT dbo.Usuario_Rol (UsuarioId, RolId) VALUES (@UsuarioId, @RolId);
        THROW 51001, 'La PK permitió una asignación duplicada.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
    END CATCH;

    BEGIN TRY
        INSERT dbo.Usuario_Rol (UsuarioId, RolId) VALUES (@UsuarioId, -1);
        THROW 51002, 'La FK permitió un rol inexistente.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 547 THROW;
    END CATCH;

    BEGIN TRY
        UPDATE dbo.Usuario SET PasswordHash = 0x01 WHERE UsuarioId = @UsuarioId;
        THROW 51003, 'El CHECK permitió un hash corto.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 547 THROW;
    END CATCH;

    BEGIN TRY
        UPDATE dbo.Token_Recuperacion SET FechaExpiracion = FechaCreacion WHERE UsuarioId = @UsuarioId;
        THROW 51004, 'El CHECK permitió expiración inválida.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 547 THROW;
    END CATCH;

    BEGIN TRY
        INSERT dbo.Bitacora_Acceso (NombreUsuarioIntentado, Resultado) VALUES (@Etiqueta, 'EXITOSO');
        THROW 51005, 'El CHECK permitió éxito sin usuario.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 547 THROW;
    END CATCH;

    BEGIN TRY
        INSERT dbo.Usuario (NombreUsuario, NombreCompleto, Correo, PasswordHash, Salt)
        VALUES (@Etiqueta + N'_2', N'Otro temporal', @Etiqueta + N'_2@example.invalid', @Hash, @Salt);
        THROW 51006, 'El UNIQUE permitió repetir la sal.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
    END CATCH;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1 AND DebeCambiarPassword = 1)
        THROW 51007, 'Defaults de Usuario incorrectos.', 1;
    IF (SELECT COUNT(*) FROM dbo.Bitacora_Acceso WHERE NombreUsuarioIntentado IN (@Etiqueta, @Etiqueta + N'_no_existe')) <> 4
        THROW 51008, 'Faltan resultados de acceso.', 1;

    ROLLBACK TRANSACTION;
    PRINT N'OK: relaciones, defaults, hash/sal, unicidad y restricciones. Datos de prueba revertidos.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
