-- Ejecutar en SSMS con una cuenta autorizada para crear bases de datos.
USE [master];
GO
IF DB_ID(N'SecureFinanceERP') IS NULL
BEGIN
    CREATE DATABASE [SecureFinanceERP];
END;
GO
