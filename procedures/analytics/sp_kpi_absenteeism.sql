/* =============================================================================
   sp_kpi_absenteeism.sql

   Returns absenteeism rate for active users between two dates.

   Output columns:
     working_days        — count of business days (excludes weekends + holidays)
     active_users        — count of users active during the window
     expected_records    — working_days * active_users
     absent_records      — count of status='absent' rows
     absenteeism_pct     — absent / expected, as DECIMAL(5,2)

   Per-program breakdown returned in second resultset.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE mart.sp_kpi_absenteeism
    @from_date DATE,
    @to_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    /* Working days: dim_date business days minus holidays */
    DECLARE @working_days INT = (
        SELECT COUNT(*)
        FROM   core.dim_date d
        LEFT   JOIN core.holiday h ON h.holiday_date = d.full_date
        WHERE  d.full_date BETWEEN @from_date AND @to_date
          AND  d.is_business_day = 1
          AND  h.holiday_date IS NULL
    );

    DECLARE @active_users INT = (
        SELECT COUNT(*) FROM core.dim_user WHERE is_active = 1
    );

    DECLARE @absent_records INT = (
        SELECT COUNT(*)
        FROM   mart.fact_daily_attendance
        WHERE  attendance_date BETWEEN @from_date AND @to_date
          AND  status = N'absent'
    );

    /* Headline KPI */
    SELECT
        @from_date                                                  AS from_date,
        @to_date                                                    AS to_date,
        @working_days                                               AS working_days,
        @active_users                                               AS active_users,
        @working_days * @active_users                               AS expected_records,
        @absent_records                                             AS absent_records,
        CAST(
            CASE WHEN @working_days * @active_users = 0 THEN 0
                 ELSE 100.0 * @absent_records / (@working_days * @active_users)
            END AS DECIMAL(5,2)
        )                                                           AS absenteeism_pct;

    /* Per-program breakdown */
    SELECT
        p.program_code,
        p.program_name,
        COUNT(DISTINCT u.user_id)                                   AS users_in_program,
        SUM(CASE WHEN f.status = N'absent' THEN 1 ELSE 0 END)       AS absences,
        CAST(
            CASE WHEN COUNT(*) = 0 THEN 0
                 ELSE 100.0 * SUM(CASE WHEN f.status = N'absent' THEN 1 ELSE 0 END) / COUNT(*)
            END AS DECIMAL(5,2)
        )                                                           AS absenteeism_pct
    FROM   core.dim_program p
    JOIN   core.dim_user u
           ON u.program_id = p.program_id AND u.is_active = 1
    LEFT JOIN mart.fact_daily_attendance f
           ON f.user_id = u.user_id
          AND f.attendance_date BETWEEN @from_date AND @to_date
    GROUP BY p.program_code, p.program_name
    ORDER BY absenteeism_pct DESC;
END
GO

PRINT N'mart.sp_kpi_absenteeism created';
GO
