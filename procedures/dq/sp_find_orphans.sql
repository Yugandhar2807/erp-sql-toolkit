/* =============================================================================
   sp_find_orphans.sql
   Generic orphan finder: rows in @child where the FK column has no match in
   @parent. Useful for tables where FKs were intentionally not enforced (common
   in legacy ERP databases) or where bulk loads bypassed FK checks.

   Returns rows in @child that violate the implicit reference.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dq.sp_find_orphans
    @child_schema  SYSNAME,
    @child_table   SYSNAME,
    @child_fk_col  SYSNAME,
    @parent_schema SYSNAME,
    @parent_table  SYSNAME,
    @parent_pk_col SYSNAME,
    @limit         INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT TOP (@limit) c.' + QUOTENAME(@child_fk_col) + N' AS orphan_value, COUNT(*) AS row_count' + NCHAR(10) +
        N'FROM ' + QUOTENAME(@child_schema) + N'.' + QUOTENAME(@child_table)  + N' c' + NCHAR(10) +
        N'WHERE NOT EXISTS (' + NCHAR(10) +
        N'    SELECT 1 FROM ' + QUOTENAME(@parent_schema) + N'.' + QUOTENAME(@parent_table) + N' p' + NCHAR(10) +
        N'    WHERE p.' + QUOTENAME(@parent_pk_col) + N' = c.' + QUOTENAME(@child_fk_col) + NCHAR(10) +
        N')' + NCHAR(10) +
        N'GROUP BY c.' + QUOTENAME(@child_fk_col) + NCHAR(10) +
        N'ORDER BY COUNT(*) DESC;';

    EXEC sp_executesql @sql, N'@limit INT', @limit = @limit;
END
GO

PRINT N'dq.sp_find_orphans created';
GO
