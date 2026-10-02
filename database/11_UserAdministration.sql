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
