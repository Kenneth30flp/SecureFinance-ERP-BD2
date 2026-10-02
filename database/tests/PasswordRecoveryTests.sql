SET NOCOUNT ON;
-- Solo ejecutar en la base temporal del runner de integración.
DECLARE @UsuarioId INT, @Codigo INT;
EXEC @Codigo = dbo.sp_RegistrarUsuario @NombreUsuario=N'password_test',
    @Correo=N'password.test@example.invalid', @NombreCompleto=N'Prueba recuperación',
    @Password=N'Anterior_2026!', @UsuarioId=@UsuarioId OUTPUT;
IF @Codigo <> 0 THROW 54100, 'No se pudo crear la cuenta de prueba.', 1;
DECLARE @SaltAnterior VARBINARY(32), @HashAnterior VARBINARY(64);
SELECT @SaltAnterior=Salt, @HashAnterior=PasswordHash FROM dbo.Usuario WHERE UsuarioId=@UsuarioId;
DECLARE @TokenHash VARBINARY(64)=HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), REPLICATE('a',64)));
DECLARE @SegundoHash VARBINARY(64)=HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), REPLICATE('b',64)));
DECLARE @TercerHash VARBINARY(64)=HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), REPLICATE('c',64)));
DECLARE @Respuesta TABLE (Generado BIT);
INSERT @Respuesta EXEC dbo.sp_SolicitarRecuperacionPassword N'no_existe', @TokenHash;
IF NOT EXISTS (SELECT 1 FROM @Respuesta WHERE Generado=0) THROW 54100, 'Cuenta inexistente aceptada.', 1;
IF EXISTS (SELECT 1 FROM dbo.Token_Recuperacion WHERE TokenHash=@TokenHash) THROW 54100, 'Token de cuenta inexistente insertado.', 1;
DELETE @Respuesta;
INSERT @Respuesta EXEC dbo.sp_SolicitarRecuperacionPassword N'password.test@example.invalid', @TokenHash;
IF NOT EXISTS (SELECT 1 FROM @Respuesta WHERE Generado=1) THROW 54100, 'Correo valido rechazado.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Token_Recuperacion WHERE TokenHash=@TokenHash AND UsuarioId=@UsuarioId
               AND DATALENGTH(TokenHash)=64 AND DATEDIFF(MINUTE,FechaCreacion,FechaExpiracion)=15)
    THROW 54100, 'Hash o expiracion incorrectos.', 1;
DECLARE @Validez TABLE (Valido BIT);
INSERT @Validez EXEC dbo.sp_ValidarTokenRecuperacion @TokenHash;
IF NOT EXISTS (SELECT 1 FROM @Validez WHERE Valido=1) THROW 54100, 'Token valido rechazado.', 1;
DELETE @Validez;
INSERT @Validez EXEC dbo.sp_ValidarTokenRecuperacion @SegundoHash;
IF EXISTS (SELECT 1 FROM @Validez WHERE Valido=1) THROW 54100, 'Token inexistente aceptado.', 1;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @SegundoHash,N'Nueva_2026!'; THROW 54100, 'Reset con token inexistente.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54001 THROW; END CATCH;
-- Invalidación al emitir una nueva solicitud.
EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test', @SegundoHash;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @TokenHash,N'Nueva_2026!'; THROW 54100, 'Reset con token invalidado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54001 THROW; END CATCH;
UPDATE dbo.Token_Recuperacion SET FechaCreacion=DATEADD(MINUTE,-30,SYSUTCDATETIME()),
    FechaExpiracion=DATEADD(MINUTE,-1,SYSUTCDATETIME()) WHERE TokenHash=@SegundoHash;
DELETE @Validez;
INSERT @Validez EXEC dbo.sp_ValidarTokenRecuperacion @SegundoHash;
IF EXISTS (SELECT 1 FROM @Validez WHERE Valido=1) THROW 54100, 'Token expirado validado.', 1;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @SegundoHash,N'Nueva_2026!'; THROW 54100, 'Reset con token expirado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54001 THROW; END CATCH;
EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test', @TercerHash;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @TercerHash,N'1234567'; THROW 54100, 'Password corto aceptado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54002 THROW; END CATCH;
DECLARE @Largo NVARCHAR(MAX)=REPLICATE(N'x',129);
BEGIN TRY EXEC dbo.sp_RestablecerPassword @TercerHash,@Largo; THROW 54100, 'Password largo truncado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54002 THROW; END CATCH;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId AND Salt=@SaltAnterior AND PasswordHash=@HashAnterior)
    THROW 54100, 'Errores de reset alteraron credenciales.', 1;
-- Conservar espacios y Unicode exactamente como el login original.
DECLARE @Nueva NVARCHAR(MAX)=N' Nueva_á_2026! ';
EXEC dbo.sp_RestablecerPassword @TercerHash,@Nueva;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId AND Salt<>@SaltAnterior AND PasswordHash<>@HashAnterior
    AND DebeCambiarPassword=0 AND FechaCambioPassword IS NOT NULL
    AND PasswordHash=HASHBYTES('SHA2_512',CONVERT(VARBINARY(256),@Nueva)+Salt))
    THROW 54100, 'Formula, salt nueva o estado incorrectos.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Token_Recuperacion WHERE TokenHash=@TercerHash AND FechaUso IS NOT NULL AND Invalidado=1)
    THROW 54100, 'Token no consumido.', 1;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @TercerHash,N'Otra_2026!'; THROW 54100, 'Token reutilizado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54001 THROW; END CATCH;
DECLARE @Login TABLE (Codigo INT, Resultado VARCHAR(30), UsuarioId INT, NombreUsuario NVARCHAR(50), Correo NVARCHAR(254), Activo BIT, DebeCambiarPassword BIT);
INSERT @Login EXEC dbo.sp_Login N'password_test',N'Anterior_2026!';
IF NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo=3) THROW 54100, 'Password anterior funciona.', 1;
DELETE @Login;
INSERT @Login EXEC dbo.sp_Login N'password_test',@Nueva;
IF NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo=0 AND DebeCambiarPassword=0) THROW 54100, 'Password nueva no funciona.', 1;
SELECT @SaltAnterior=Salt,@HashAnterior=PasswordHash FROM dbo.Usuario WHERE UsuarioId=@UsuarioId;
DECLARE @CambioHash VARBINARY(64)=HASHBYTES('SHA2_512',CONVERT(VARBINARY(MAX),REPLICATE('e',64)));
EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test',@CambioHash;
BEGIN TRY EXEC dbo.sp_CambiarPassword @UsuarioId,N'Incorrecta_2026!',N'Cambio_2026!'; THROW 54100, 'Password actual incorrecta aceptada.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54003 THROW; END CATCH;
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId AND Salt=@SaltAnterior AND PasswordHash=@HashAnterior)
    THROW 54100, 'Cambio fallido altero credenciales.', 1;
EXEC dbo.sp_CambiarPassword @UsuarioId,@Nueva,N'Cambio_2026!';
IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId=@UsuarioId AND Salt<>@SaltAnterior AND PasswordHash<>@HashAnterior AND DebeCambiarPassword=0)
    THROW 54100, 'Cambio autenticado no renovo salt/hash.', 1;
IF EXISTS (SELECT 1 FROM dbo.Token_Recuperacion WHERE UsuarioId=@UsuarioId AND Invalidado=0)
    THROW 54100, 'Cambio autenticado dejo tokens utilizables.', 1;
DELETE @Login;
INSERT @Login EXEC dbo.sp_Login N'password_test',@Nueva;
IF NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo=3) THROW 54100, 'Credencial reemplazada funciona.', 1;
DELETE @Login;
INSERT @Login EXEC dbo.sp_Login N'password_test',N'Cambio_2026!';
IF NOT EXISTS (SELECT 1 FROM @Login WHERE Codigo=0) THROW 54100, 'Cambio autenticado no permite login.', 1;
-- Cuenta inactiva y fechas de uso: mismo rechazo de token, sin revelar el motivo.
DECLARE @CuartoHash VARBINARY(64)=HASHBYTES('SHA2_512',CONVERT(VARBINARY(MAX),REPLICATE('d',64)));
EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test',@CuartoHash;
UPDATE dbo.Token_Recuperacion SET FechaUso=SYSUTCDATETIME() WHERE TokenHash=@CuartoHash;
BEGIN TRY EXEC dbo.sp_RestablecerPassword @CuartoHash,N'Nueva_2026!'; THROW 54100, 'Token con FechaUso aceptado.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54001 THROW; END CATCH;
UPDATE dbo.Usuario SET Activo=0 WHERE UsuarioId=@UsuarioId;
BEGIN TRY EXEC dbo.sp_CambiarPassword @UsuarioId,N'Cambio_2026!',N'Nueva_2026!'; THROW 54100, 'Cuenta inactiva cambio password.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 54003 THROW; END CATCH;
UPDATE dbo.Usuario SET Activo=1 WHERE UsuarioId=@UsuarioId;
-- Verificar la cadena de propiedad dbo con exactamente los cuatro EXECUTE nuevos.
CREATE USER [password_test_app] WITHOUT LOGIN;
GRANT EXECUTE ON OBJECT::dbo.sp_SolicitarRecuperacionPassword TO [password_test_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ValidarTokenRecuperacion TO [password_test_app];
GRANT EXECUTE ON OBJECT::dbo.sp_RestablecerPassword TO [password_test_app];
GRANT EXECUTE ON OBJECT::dbo.sp_CambiarPassword TO [password_test_app];
DECLARE @PermisoHash VARBINARY(64)=HASHBYTES('SHA2_512',CONVERT(VARBINARY(MAX),REPLICATE('f',64)));
EXECUTE AS USER=N'password_test_app';
EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test',@PermisoHash;
EXEC dbo.sp_ValidarTokenRecuperacion @PermisoHash;
EXEC dbo.sp_RestablecerPassword @PermisoHash,N'Permiso_2026!';
EXEC dbo.sp_CambiarPassword @UsuarioId,N'Permiso_2026!',N'Cambio_2026!';
BEGIN TRY SELECT UsuarioId FROM dbo.Usuario; THROW 54100, 'SELECT directo permitido.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 229 THROW; END CATCH;
BEGIN TRY SELECT TokenHash FROM dbo.Token_Recuperacion; THROW 54100, 'SELECT tokens permitido.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 229 THROW; END CATCH;
BEGIN TRY UPDATE dbo.Usuario SET Activo=1 WHERE UsuarioId=@UsuarioId; THROW 54100, 'UPDATE directo permitido.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 229 THROW; END CATCH;
IF HAS_PERMS_BY_NAME(N'dbo.Token_Recuperacion',N'OBJECT',N'INSERT')<>0
   OR HAS_PERMS_BY_NAME(N'dbo.Token_Recuperacion',N'OBJECT',N'DELETE')<>0
    THROW 54100, 'Permisos directos sobre tokens.', 1;
REVERT;
PRINT 'OK: solicitud, hash de token, expiracion, uso unico, rollback, salt/hash nuevos y login compatible.';
GO
