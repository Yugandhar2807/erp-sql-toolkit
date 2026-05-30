/* =============================================================================
   vw_finance_summary.sql
   Per-user finance summary view: total invoiced, total collected, outstanding,
   oldest open invoice age, count of open invoices.  One row per user.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER VIEW mart.vw_finance_summary
AS
WITH agg AS (
    SELECT
        i.user_id,
        SUM(i.amount)              AS invoiced,
        SUM(i.amount - i.balance)  AS collected,
        SUM(i.balance)             AS outstanding,
        SUM(CASE WHEN i.balance > 0 THEN 1 ELSE 0 END) AS open_invoice_count,
        MIN(CASE WHEN i.balance > 0 THEN i.due_date END) AS oldest_open_due_date
    FROM   core.fact_invoice i
    GROUP BY i.user_id
)
SELECT
    u.user_id,
    u.external_ref,
    u.full_name,
    u.role,
    p.program_code,
    p.program_name,
    a.invoiced,
    a.collected,
    a.outstanding,
    a.open_invoice_count,
    a.oldest_open_due_date,
    CASE
        WHEN a.oldest_open_due_date IS NULL THEN 0
        ELSE DATEDIFF(DAY, a.oldest_open_due_date, SYSDATETIME())
    END AS oldest_open_age_days
FROM   core.dim_user      u
LEFT   JOIN core.dim_program p ON p.program_id = u.program_id
LEFT   JOIN agg            a ON a.user_id    = u.user_id;
GO
PRINT N'mart.vw_finance_summary created';
GO
