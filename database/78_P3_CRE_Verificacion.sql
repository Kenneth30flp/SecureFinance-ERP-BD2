-- READ ONLY post-install checks. NOT EXECUTED. Does not install or repair anything.
SET XACT_ABORT ON;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT=0 THROW 57000,'Laboratorio y transaccion externa requeridos.',1;
IF OBJECT_ID('dbo.P3_CRE_ConvertirCotizacionCredito','P') IS NULL THROW 57000,'Falta conversion publica 77.',1;
IF OBJECT_ID('dbo.P3_CRE_ConsultarCaja','P') IS NULL THROW 57000,'Falta consulta de caja propia 74.',1;
IF EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta c OUTER APPLY(SELECT SUM(Importe-Abonado) Saldo FROM dbo.P3_CRE_Cuota q WHERE q.FacturaId=c.FacturaId) q WHERE c.Saldo<>q.Saldo OR q.Saldo IS NULL)
 THROW 57000,'Cuenta y cuotas no concilian.',1;
IF EXISTS(SELECT 1 FROM dbo.Credito_Cliente c CROSS APPLY(SELECT SUM(Saldo) Deuda FROM dbo.P3_CRE_Cuenta x WHERE x.ClienteId=c.ClienteId) d WHERE d.Deuda>c.Limite)
 THROW 57000,'Deuda superior al limite autorizado.',1;
IF EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta c JOIN dbo.MovimientoCaja m ON m.FacturaId=c.FacturaId)
 THROW 57000,'Venta de credito registrada como contado.',1;
IF EXISTS(SELECT 1 FROM dbo.Abono_Factura a LEFT JOIN dbo.P3_CRE_ReciboCaja r ON r.AbonoId=a.AbonoId
 OUTER APPLY(SELECT SUM(Monto) Monto FROM dbo.P3_CRE_AplicacionCuota x WHERE x.AbonoId=a.AbonoId) x
 WHERE r.AbonoId IS NULL OR r.Monto<>a.Monto OR x.Monto IS NULL OR x.Monto<>a.Monto)
 THROW 57000,'Recibos o aplicaciones no concilian.',1;
SELECT N'Verificacion estructural completada; no acredita concurrencia ni navegador.' Resultado;
SELECT o.name,o.type_desc FROM sys.objects o WHERE o.schema_id=SCHEMA_ID('dbo') AND
 (o.name LIKE 'P3[_]CRE[_]%' OR o.name IN('Credito_Cliente','Abono_Factura','sp_RegistrarAbonoCliente')) ORDER BY o.type_desc,o.name;
SELECT r.Nombre,p.Codigo FROM dbo.Rol r JOIN dbo.Rol_Permiso rp ON rp.RolId=r.RolId JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId
 WHERE p.Codigo LIKE 'CREDITOS[_]%' ORDER BY r.Nombre,p.Codigo;
