USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Ejecutar con cuenta de desarrollo, después de 03. No depende de semillas.
-- Rollback también revierte los accesos de esta prueba; IDENTITY puede avanzar.
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @Tag NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
    DECLARE @Nombre NVARCHAR(50) = N't1_' + @Tag, @Otro NVARCHAR(50) = N't2_' + @Tag,
            @Ausente NVARCHAR(50) = N'no_' + @Tag,
            @Correo NVARCHAR(254) = @Tag + N'@example.invalid',
            @Correo2 NVARCHAR(254) = @Tag + N'2@example.invalid',
            @Password NVARCHAR(MAX) = N' Prueba_á漢_2026! ', @Id INT, @Id2 INT, @Rc INT;
    DECLARE @Registro TABLE (Codigo INT, Resultado VARCHAR(40), UsuarioId INT);
    INSERT @Registro EXEC @Rc = dbo.sp_RegistrarUsuario @Nombre, @Correo, @Password, N'Prueba uno', @Id OUTPUT;
    IF @Rc <> 0 OR @Id IS NULL OR NOT EXISTS (SELECT 1 FROM @Registro WHERE Codigo = 0 AND UsuarioId = @Id)
        THROW 51200, 'Registro correcto falló.', 1;
    DELETE FROM @Registro;
    INSERT @Registro EXEC @Rc = dbo.sp_RegistrarUsuario @Otro, @Correo2, @Password, N'Prueba dos', @Id2 OUTPUT;
    IF @Rc <> 0 OR @Id2 IS NULL THROW 51201, 'Segundo registro falló.', 1;
    IF (SELECT COUNT(*) FROM dbo.Usuario WHERE UsuarioId IN (@Id, @Id2)
        AND PasswordHash IS NOT NULL AND DATALENGTH(PasswordHash) = 64
        AND Salt IS NOT NULL AND DATALENGTH(Salt) = 32
        AND PasswordHash = HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + Salt)) <> 2
        THROW 51202, 'Hash, sal o fórmula incorrectos.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario a JOIN dbo.Usuario b ON a.Salt = b.Salt OR a.PasswordHash = b.PasswordHash
               WHERE a.UsuarioId = @Id AND b.UsuarioId = @Id2)
        THROW 51203, 'Dos usuarios comparten sal o hash.', 1;

    DECLARE @Ignorado INT;
    DELETE FROM @Registro;
    INSERT @Registro EXEC @Rc = dbo.sp_RegistrarUsuario @Nombre, @Correo2, @Password, N'Duplicado', @Ignorado OUTPUT;
    IF @Rc <> 11 OR @Ignorado IS NOT NULL THROW 51204, 'Duplicado no rechazado.', 1;
    DECLARE @Largo NVARCHAR(MAX) = REPLICATE(N'x', 129);
    DELETE FROM @Registro;
    INSERT @Registro EXEC @Rc = dbo.sp_RegistrarUsuario @Ausente, @Correo, @Largo, N'Inválido', @Ignorado OUTPUT;
    IF @Rc <> 10 THROW 51205, 'Password demasiado largo no rechazado.', 1;

    -- Contrato público exacto, sin columnas secretas, incluso en metadatos.
    IF (SELECT COUNT(*) FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.sp_Login'), 0)
        WHERE is_hidden = 0) <> 7
        THROW 51206, 'Contrato de columnas de login incorrecto.', 1;
    IF EXISTS (SELECT 1 FROM sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.sp_Login'), 0)
               WHERE error_number IS NOT NULL OR name NOT IN
               (N'Codigo', N'Resultado', N'UsuarioId', N'NombreUsuario', N'Correo', N'Activo', N'DebeCambiarPassword'))
        THROW 51207, 'Login devuelve columnas no autorizadas o metadatos inválidos.', 1;
    DECLARE @Login TABLE (Codigo INT, Resultado VARCHAR(30), UsuarioId INT,
                         NombreUsuario NVARCHAR(50), Correo NVARCHAR(254), Activo BIT, DebeCambiarPassword BIT);
    INSERT @Login EXEC @Rc = dbo.sp_Login @Nombre, @Password;
    IF @Rc <> 0 OR NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo = 0 AND Resultado = 'EXITOSO'
                              AND UsuarioId = @Id AND NombreUsuario = @Nombre AND Correo = @Correo
                              AND Activo = 1 AND DebeCambiarPassword = 1)
        THROW 51208, 'Login correcto falló.', 1;
    DELETE FROM @Login;
    INSERT @Login EXEC @Rc = dbo.sp_Login @Nombre, N'Incorrecta';
    IF @Rc <> 3 OR NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo = 3 AND Resultado = 'PASSWORD_INCORRECTA'
                              AND UsuarioId IS NULL AND NombreUsuario IS NULL AND Correo IS NULL)
        THROW 51209, 'Password incorrecto no controlado.', 1;
    DELETE FROM @Login;
    INSERT @Login EXEC @Rc = dbo.sp_Login @Ausente, @Password;
    IF @Rc <> 1 OR NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo = 1 AND Resultado = 'USUARIO_INEXISTENTE')
        THROW 51210, 'Usuario inexistente no controlado.', 1;
    UPDATE dbo.Usuario SET Activo = 0 WHERE UsuarioId = @Id;
    DELETE FROM @Login;
    INSERT @Login EXEC @Rc = dbo.sp_Login @Nombre, @Password;
    IF @Rc <> 2 OR NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo = 2 AND Resultado = 'USUARIO_INACTIVO')
        THROW 51211, 'Usuario inactivo no controlado.', 1;
    IF (SELECT COUNT(*) FROM dbo.Bitacora_Acceso WHERE NombreUsuarioIntentado IN (@Nombre, @Ausente)) <> 4
        THROW 51212, 'No se registró exactamente un acceso por intento.', 1;
    IF EXISTS (SELECT Resultado FROM (VALUES ('EXITOSO'), ('PASSWORD_INCORRECTA'),
                    ('USUARIO_INEXISTENTE'), ('USUARIO_INACTIVO')) AS e(Resultado)
               EXCEPT SELECT Resultado FROM dbo.Bitacora_Acceso WHERE NombreUsuarioIntentado IN (@Nombre, @Ausente))
        THROW 51213, 'Falta un resultado de bitácora.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Bitacora_Acceso WHERE NombreUsuarioIntentado IN (@Nombre, @Ausente)
               AND (FechaHora IS NULL OR UsuarioSQL IS NULL
                    OR (Resultado = 'USUARIO_INEXISTENTE' AND UsuarioId IS NOT NULL)
                    OR (Resultado <> 'USUARIO_INEXISTENTE' AND (UsuarioId IS NULL OR UsuarioId <> @Id))))
        THROW 51214, 'Metadatos o identidad de bitácora incorrectos.', 1;

    DECLARE @R1 INT, @R2 INT, @P1 INT, @P2 INT;
    INSERT dbo.Rol (Nombre) VALUES (@Nombre);
    SET @R1 = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Rol (Nombre) VALUES (@Otro);
    SET @R2 = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Permiso (Codigo) VALUES (@Nombre);
    SET @P1 = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Permiso (Codigo, Activo) VALUES (@Otro, 0);
    SET @P2 = CONVERT(INT, SCOPE_IDENTITY());
    INSERT dbo.Usuario_Rol (UsuarioId, RolId) VALUES (@Id, @R1), (@Id, @R2);
    INSERT dbo.Rol_Permiso (RolId, PermisoId) VALUES (@R1, @P1), (@R2, @P1), (@R1, @P2);
    DECLARE @Permisos TABLE (PermisoId INT, Codigo NVARCHAR(100));
    INSERT @Permisos EXEC dbo.sp_ObtenerPermisosUsuario @Id;
    IF EXISTS (SELECT 1 FROM @Permisos) THROW 51215, 'Usuario inactivo obtuvo permisos.', 1;
    UPDATE dbo.Usuario SET Activo = 1 WHERE UsuarioId = @Id;
    INSERT @Permisos EXEC dbo.sp_ObtenerPermisosUsuario @Id;
    IF (SELECT COUNT(*) FROM @Permisos) <> 1 OR NOT EXISTS (SELECT 1 FROM @Permisos WHERE PermisoId = @P1)
        THROW 51216, 'Permisos duplicados o permiso inactivo incluido.', 1;
    DELETE FROM @Permisos;
    UPDATE dbo.Rol SET Activo = 0 WHERE RolId IN (@R1, @R2);
    INSERT @Permisos EXEC dbo.sp_ObtenerPermisosUsuario @Id;
    IF EXISTS (SELECT 1 FROM @Permisos) THROW 51217, 'Rol inactivo concedió permisos.', 1;
    INSERT @Permisos EXEC dbo.sp_ObtenerPermisosUsuario @Id2;
    IF EXISTS (SELECT 1 FROM @Permisos) THROW 51218, 'Usuario sin roles obtuvo permisos.', 1;
    ROLLBACK TRANSACTION;
    PRINT N'OK: Fase 2, registro, SHA2_512, sales únicas, login, bitácora y permisos. Datos revertidos.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
