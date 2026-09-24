USE [SecureFinanceERP];
GO
-- Usuario existente; las consultas usan la cadena de propiedad dbo.
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaTransacciones TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarHistoricoVentas TO [securefinance_app];
GO
