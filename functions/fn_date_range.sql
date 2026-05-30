/* =============================================================================
   fn_date_range.sql
   Inline TVF: generates a row per date between two dates, inclusive.
   Uses a recursive CTE; safe for ranges up to ~32k days.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER FUNCTION util.fn_date_range
(
    @from DATE,
    @to   DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH dates AS (
        SELECT @from AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d)
        FROM   dates
        WHERE  d < @to
    )
    SELECT d AS full_date FROM dates
);
GO
PRINT N'util.fn_date_range created.  Note: caller must use OPTION (MAXRECURSION 0) for ranges > 100 days.';
GO
