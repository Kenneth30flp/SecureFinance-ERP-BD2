-- Laboratory authorization. Provisioned only by the isolated installer after server/DB identity checks.
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.P3_INT_Destino() RETURNS NVARCHAR(128)
AS
BEGIN
 DECLARE @Bound NVARCHAR(256)=(SELECT CONVERT(NVARCHAR(256),value) FROM sys.extended_properties WHERE class=0 AND name=N'P3.Integracion.Autorizacion');
 RETURN CASE WHEN DB_ID()>4 AND DB_NAME() LIKE N'SecureFinanceERP[_]P3[_]PRO[_]%'
  AND @Bound=CONCAT(CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName')),N'|',DB_NAME())
  THEN DB_NAME() ELSE N'!LABORATORIO_NO_AUTORIZADO!' END;
END;
GO
