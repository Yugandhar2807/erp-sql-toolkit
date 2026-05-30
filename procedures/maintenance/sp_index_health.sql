/* =============================================================================
   sp_index_health.sql
   Reports index fragmentation. Useful before/after a maintenance window.
   Mode: 'LIMITED' (fast, default) or 'SAMPLED' (more accurate, slower).
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE util.sp_index_health
    @mode NVARCHAR(20) = N'LIMITED'                            -- LIMITED | SAMPLED | DETAILED
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.name              AS schema_name,
        t.name              AS table_name,
        i.name              AS index_name,
        i.type_desc         AS index_type,
        ps.avg_fragmentation_in_percent,
        ps.page_count,
        ps.record_count,
        CASE
            WHEN ps.avg_fragmentation_in_percent < 5  THEN N'OK'
            WHEN ps.avg_fragmentation_in_percent < 30 THEN N'REORGANIZE'
            ELSE                                           N'REBUILD'
        END AS recommendation
    FROM   sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, @mode) ps
    JOIN   sys.indexes i
           ON i.object_id = ps.object_id AND i.index_id = ps.index_id
    JOIN   sys.tables   t ON t.object_id = i.object_id
    JOIN   sys.schemas  s ON s.schema_id = t.schema_id
    WHERE  i.index_id > 0                                       -- skip heaps
      AND  ps.page_count >= 100                                 -- skip tiny indexes
    ORDER BY ps.avg_fragmentation_in_percent DESC;
END
GO

PRINT N'util.sp_index_health created';
GO
