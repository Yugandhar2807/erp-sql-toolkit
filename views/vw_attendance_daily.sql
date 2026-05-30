/* =============================================================================
   vw_attendance_daily.sql
   Friendly join-flat view over mart.fact_daily_attendance with the user, program,
   and date context that a Power BI or Excel consumer would want.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER VIEW mart.vw_attendance_daily
AS
SELECT
    f.attendance_date,
    d.day_name,
    d.is_weekend,
    f.user_id,
    u.external_ref,
    u.full_name,
    u.role,
    p.program_code,
    p.program_name,
    f.first_in,
    f.last_out,
    f.duration_minutes,
    f.status
FROM   mart.fact_daily_attendance f
JOIN   core.dim_user    u ON u.user_id    = f.user_id
LEFT   JOIN core.dim_program p ON p.program_id = u.program_id
JOIN   core.dim_date    d ON d.full_date  = f.attendance_date;
GO
PRINT N'mart.vw_attendance_daily created';
GO
