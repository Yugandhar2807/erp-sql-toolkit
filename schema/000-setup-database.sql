/* =============================================================================
   000-setup-database.sql
   Drops + recreates the demo database used by every script in this toolkit.
   Run this once on a personal SQL Server instance — NEVER on a shared/prod DB.
   ============================================================================= */

SET NOCOUNT ON;
GO

USE master;
GO

-- Force-disconnect any existing sessions and drop
IF DB_ID(N'ERPToolkitDemo') IS NOT NULL
BEGIN
    ALTER DATABASE ERPToolkitDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ERPToolkitDemo;
END
GO

CREATE DATABASE ERPToolkitDemo;
GO

ALTER DATABASE ERPToolkitDemo SET RECOVERY SIMPLE;        -- demo only, less log overhead
ALTER DATABASE ERPToolkitDemo SET READ_COMMITTED_SNAPSHOT ON;
GO

USE ERPToolkitDemo;
GO

-- Schemas
IF SCHEMA_ID(N'core')   IS NULL EXEC(N'CREATE SCHEMA core   AUTHORIZATION dbo;');
IF SCHEMA_ID(N'stg')    IS NULL EXEC(N'CREATE SCHEMA stg    AUTHORIZATION dbo;');
IF SCHEMA_ID(N'audit')  IS NULL EXEC(N'CREATE SCHEMA audit  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'mart')   IS NULL EXEC(N'CREATE SCHEMA mart   AUTHORIZATION dbo;');
IF SCHEMA_ID(N'util')   IS NULL EXEC(N'CREATE SCHEMA util   AUTHORIZATION dbo;');
IF SCHEMA_ID(N'dq')     IS NULL EXEC(N'CREATE SCHEMA dq     AUTHORIZATION dbo;');
GO

PRINT N'ERPToolkitDemo database created. Schemas: core, stg, audit, mart, util, dq';
GO
