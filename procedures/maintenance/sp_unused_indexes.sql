/* =============================================================================
   sp_unused_indexes.sql
   Reports non-clustered indexes that have writes but ZERO reads since SQL Server
   was last restarted. Candidates for DROP after a sufficient observation period.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE util.sp_unused_indexes
    @min_user_updates INT = 100                                 -- ignore noisy small writes
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.name                                       AS schema_name,
        t.name                                       AS table_name,
        i.name                                       AS index_name,
        i.type_desc                                  AS index_type,
        ISNULL(us.user_seeks, 0)                     AS user_seeks,
        ISNULL(us.user_scans, 0)                     AS user_scans,
        ISNULL(us.user_lookups, 0)                   AS user_lookups,
        ISNULL(us.user_updates, 0)                   AS user_updates,
        N'DROP INDEX ' + QUOTENAME(i.name) + N' ON '
        + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';' AS suggested_drop_statement
    FROM   sys.indexes i
    JOIN   sys.tables  t ON t.object_id = i.object_id
    JOIN   sys.schemas s ON s.schema_id = t.schema_id
    LEFT   JOIN sys.dm_db_index_usage_stats us
           ON us.object_id = i.object_id
          AND us.index_id  = i.index_id
          AND us.database_id = DB_ID()
    WHERE  i.index_id > 1                                       -- skip clustered + heaps
      AND  i.is_primary_key = 0
      AND  i.is_unique_constraint = 0
      AND  ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) = 0
      AND  ISNULL(us.user_updates, 0) >= @min_user_updates
    ORDER BY us.user_updates DESC;
END
GO

PRINT N'util.sp_unused_indexes created';
GO
