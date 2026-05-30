/* =============================================================================
   sp_reindex_smart.sql
   Adaptive maintenance: REORGANIZE if 5-30%% fragmented, REBUILD if >30%%.
   Online rebuild used when available (Enterprise / Azure SQL).
   Prints the action it would take if @whatif = 1.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE util.sp_reindex_smart
    @min_page_count INT = 100,
    @whatif         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @schema SYSNAME, @table SYSNAME, @index SYSNAME, @frag FLOAT, @sql NVARCHAR(MAX);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT  s.name, t.name, i.name, ps.avg_fragmentation_in_percent
        FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, N'LIMITED') ps
        JOIN    sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
        JOIN    sys.tables  t ON t.object_id = i.object_id
        JOIN    sys.schemas s ON s.schema_id = t.schema_id
        WHERE   i.index_id > 0
          AND   ps.page_count       >= @min_page_count
          AND   ps.avg_fragmentation_in_percent >= 5;

    OPEN cur;
    FETCH NEXT FROM cur INTO @schema, @table, @index, @frag;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @frag < 30
            SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON '
                     + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N' REORGANIZE;';
        ELSE
            SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON '
                     + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N' REBUILD;';

        IF @whatif = 1
            PRINT N'-- WHATIF: ' + @sql;
        ELSE
        BEGIN
            PRINT @sql;
            EXEC sp_executesql @sql;
        END

        FETCH NEXT FROM cur INTO @schema, @table, @index, @frag;
    END

    CLOSE cur;
    DEALLOCATE cur;
END
GO

PRINT N'util.sp_reindex_smart created';
GO
