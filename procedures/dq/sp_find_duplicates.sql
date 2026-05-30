/* =============================================================================
   sp_find_duplicates.sql
   Generic duplicate finder: groups rows in @table by a comma-separated list of
   columns and returns groups with COUNT > 1.

   Example:
     EXEC dq.sp_find_duplicates
         @table_schema = N'core',
         @table_name   = N'dim_user',
         @key_cols     = N'email';
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE dq.sp_find_duplicates
    @table_schema SYSNAME,
    @table_name   SYSNAME,
    @key_cols     NVARCHAR(MAX),                                -- comma-separated
    @limit        INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    /* Build a safe quoted column list */
    DECLARE @quoted NVARCHAR(MAX) = N'';
    SELECT  @quoted = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), N', ')
    FROM    STRING_SPLIT(@key_cols, N',')
    WHERE   LTRIM(RTRIM(value)) <> N'';

    IF @quoted IS NULL OR @quoted = N''
    BEGIN
        RAISERROR(N'@key_cols must contain at least one column name.', 16, 1);
        RETURN;
    END

    DECLARE @sql NVARCHAR(MAX) =
        N'SELECT TOP (@limit) ' + @quoted + N', COUNT(*) AS dup_count' + NCHAR(10) +
        N'FROM '   + QUOTENAME(@table_schema) + N'.' + QUOTENAME(@table_name) + NCHAR(10) +
        N'GROUP BY ' + @quoted + NCHAR(10) +
        N'HAVING COUNT(*) > 1' + NCHAR(10) +
        N'ORDER BY COUNT(*) DESC;';

    EXEC sp_executesql @sql, N'@limit INT', @limit = @limit;
END
GO

PRINT N'dq.sp_find_duplicates created';
GO
