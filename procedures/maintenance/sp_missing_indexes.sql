/* =============================================================================
   sp_missing_indexes.sql
   Reports SQL Server's "you might want this index" recommendations from the
   DMV sys.dm_db_missing_index_*. Sorted by impact_score (higher = bigger win).
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE util.sp_missing_indexes
    @top_n INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@top_n)
        DB_NAME(mid.database_id)                                AS database_name,
        OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id)      AS schema_name,
        OBJECT_NAME(mid.object_id, mid.database_id)             AS table_name,
        migs.user_seeks,
        migs.user_scans,
        migs.avg_total_user_cost,
        migs.avg_user_impact,
        /* Heuristic Microsoft published a long time ago — useful relative ordering */
        ROUND(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans), 0)
                                                                AS impact_score,
        mid.equality_columns,
        mid.inequality_columns,
        mid.included_columns,
        N'CREATE INDEX ix_' + REPLACE(OBJECT_NAME(mid.object_id, mid.database_id), N' ', N'_')
            + N'_suggested ON '
            + QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id))
            + N'.'
            + QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id))
            + N' (' + ISNULL(mid.equality_columns + ISNULL(N', ' + mid.inequality_columns, N''), mid.inequality_columns) + N')'
            + ISNULL(N' INCLUDE (' + mid.included_columns + N')', N'')
            + N';'                                              AS suggested_create_statement
    FROM   sys.dm_db_missing_index_details      mid
    JOIN   sys.dm_db_missing_index_groups       mig  ON mig.index_handle = mid.index_handle
    JOIN   sys.dm_db_missing_index_group_stats  migs ON migs.group_handle = mig.index_group_handle
    WHERE  mid.database_id = DB_ID()
    ORDER BY impact_score DESC;
END
GO

PRINT N'util.sp_missing_indexes created';
GO
