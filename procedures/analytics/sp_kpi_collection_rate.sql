/* =============================================================================
   sp_kpi_collection_rate.sql

   Finance KPI: how much of what was invoiced has been collected, for a window.

   Returns:
     - Headline: invoiced, collected, collection_pct, outstanding_balance
     - Aging buckets: 0-30, 31-60, 61-90, 90+
     - Top-N programs by outstanding balance
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE mart.sp_kpi_collection_rate
    @from_date DATE,
    @to_date   DATE,
    @top_n     INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    /* Headline */
    SELECT
        @from_date                                              AS from_date,
        @to_date                                                AS to_date,
        SUM(i.amount)                                           AS invoiced,
        SUM(i.amount - i.balance)                               AS collected,
        SUM(i.balance)                                          AS outstanding_balance,
        CAST(
            CASE WHEN SUM(i.amount) = 0 THEN 0
                 ELSE 100.0 * SUM(i.amount - i.balance) / SUM(i.amount)
            END AS DECIMAL(5,2)
        )                                                       AS collection_pct
    FROM core.fact_invoice i
    WHERE i.invoice_date BETWEEN @from_date AND @to_date;

    /* Aging buckets on currently-open balance */
    DECLARE @today DATE = SYSDATETIME();

    SELECT
        bucket,
        COUNT(*)         AS invoice_count,
        SUM(balance)     AS outstanding
    FROM (
        SELECT
            CASE
                WHEN DATEDIFF(DAY, i.due_date, @today) <= 30 THEN N'0-30'
                WHEN DATEDIFF(DAY, i.due_date, @today) <= 60 THEN N'31-60'
                WHEN DATEDIFF(DAY, i.due_date, @today) <= 90 THEN N'61-90'
                ELSE                                              N'90+'
            END AS bucket,
            i.balance
        FROM core.fact_invoice i
        WHERE i.balance > 0
    ) x
    GROUP BY bucket
    ORDER BY CASE bucket
        WHEN N'0-30'  THEN 1
        WHEN N'31-60' THEN 2
        WHEN N'61-90' THEN 3
        ELSE 4
    END;

    /* Top-N programs by outstanding balance */
    SELECT TOP (@top_n)
        p.program_code,
        p.program_name,
        SUM(i.balance) AS outstanding
    FROM core.fact_invoice i
    JOIN core.dim_user    u ON u.user_id    = i.user_id
    JOIN core.dim_program p ON p.program_id = u.program_id
    WHERE i.balance > 0
    GROUP BY p.program_code, p.program_name
    ORDER BY SUM(i.balance) DESC;
END
GO

PRINT N'mart.sp_kpi_collection_rate created';
GO
