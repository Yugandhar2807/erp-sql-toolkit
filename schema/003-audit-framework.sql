/* =============================================================================
   003-audit-framework.sql

   Generic audit framework: one table + one trigger template you can attach to
   any source table to capture every INSERT / UPDATE / DELETE with before/after
   JSON payload, the user who did it, and a timestamp.

   To attach to a table:
     EXEC audit.sp_generate_audit_trigger @table_schema='core', @table_name='dim_user';

   The procedure prints the CREATE TRIGGER statement; review and execute it.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'audit.row_audit', N'U') IS NOT NULL DROP TABLE audit.row_audit;
GO
CREATE TABLE audit.row_audit
(
    audit_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    happened_at       DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    happened_by       NVARCHAR(128)  NOT NULL DEFAULT SUSER_SNAME(),
    table_schema      SYSNAME        NOT NULL,
    table_name        SYSNAME        NOT NULL,
    op                CHAR(1)        NOT NULL CHECK (op IN ('I','U','D')),
    pk_json           NVARCHAR(400)  NOT NULL,                  -- key snapshot (JSON)
    before_json       NVARCHAR(MAX)  NULL,                      -- row before (NULL for INSERT)
    after_json        NVARCHAR(MAX)  NULL,                      -- row after  (NULL for DELETE)
    host_name         NVARCHAR(128)  NOT NULL DEFAULT HOST_NAME(),
    program_name      NVARCHAR(128)  NOT NULL DEFAULT PROGRAM_NAME()
);
GO

CREATE INDEX ix_row_audit_table_time
    ON audit.row_audit(table_schema, table_name, happened_at DESC);
GO

PRINT N'audit.row_audit created';
GO

/* ---------- sp_generate_audit_trigger -------------------------------------
   Outputs (via PRINT) a CREATE TRIGGER statement that you copy/paste and run.
   Why "print, don't auto-run"?  Safer:  you review what gets created.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE audit.sp_generate_audit_trigger
    @table_schema SYSNAME,
    @table_name   SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @qualified NVARCHAR(260) = QUOTENAME(@table_schema) + N'.' + QUOTENAME(@table_name);
    DECLARE @trigger_name SYSNAME = N'trg_audit_' + @table_schema + N'_' + @table_name;

    IF OBJECT_ID(@qualified, N'U') IS NULL
    BEGIN
        RAISERROR(N'Table %s does not exist.', 16, 1, @qualified);
        RETURN;
    END

    -- Build the PK column list as JSON for the audit row
    DECLARE @pk_cols NVARCHAR(MAX);
    SELECT @pk_cols = STRING_AGG(QUOTENAME(c.name), N', ')
    FROM   sys.indexes        i
    JOIN   sys.index_columns  ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    JOIN   sys.columns        c  ON c.object_id  = i.object_id AND c.column_id = ic.column_id
    WHERE  i.object_id = OBJECT_ID(@qualified)
      AND  i.is_primary_key = 1;

    IF @pk_cols IS NULL
    BEGIN
        RAISERROR(N'Table %s has no primary key; audit trigger requires a PK.', 16, 1, @qualified);
        RETURN;
    END

    DECLARE @sql NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER ' + QUOTENAME(@table_schema) + N'.' + QUOTENAME(@trigger_name) + N'
ON ' + @qualified + N'
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: rows in inserted, none in deleted
    INSERT INTO audit.row_audit (table_schema, table_name, op, pk_json, before_json, after_json)
    SELECT N''' + @table_schema + N''', N''' + @table_name + N''', ''I'',
           (SELECT ' + @pk_cols + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           NULL,
           (SELECT * FROM inserted i2 WHERE EXISTS (SELECT 1 FROM (SELECT i.*) x WHERE 1=1) FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM   inserted i
    WHERE  NOT EXISTS (SELECT 1 FROM deleted);

    -- UPDATE: rows in both
    INSERT INTO audit.row_audit (table_schema, table_name, op, pk_json, before_json, after_json)
    SELECT N''' + @table_schema + N''', N''' + @table_name + N''', ''U'',
           (SELECT ' + @pk_cols + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT * FROM deleted  WHERE 1=1 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT * FROM inserted WHERE 1=1 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM   inserted i
    WHERE  EXISTS (SELECT 1 FROM deleted);

    -- DELETE: rows only in deleted
    INSERT INTO audit.row_audit (table_schema, table_name, op, pk_json, before_json, after_json)
    SELECT N''' + @table_schema + N''', N''' + @table_name + N''', ''D'',
           (SELECT ' + @pk_cols + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT * FROM deleted WHERE 1=1 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           NULL
    FROM   deleted d
    WHERE  NOT EXISTS (SELECT 1 FROM inserted);
END
';

    PRINT N'-- Generated trigger for ' + @qualified + N'.  Review and execute:';
    PRINT @sql;
END
GO

PRINT N'audit.sp_generate_audit_trigger created.  Usage: EXEC audit.sp_generate_audit_trigger @table_schema=N''core'', @table_name=N''dim_user'';';
GO
