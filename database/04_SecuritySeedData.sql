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
