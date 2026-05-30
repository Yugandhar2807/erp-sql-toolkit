/* =============================================================================
   sp_close_attendance_day.sql

   Daily-close roll-up: turns fact_punch (raw IN/OUT events) into one row per
   user per day in mart.fact_daily_attendance with status and duration.

   Idempotent for a given (@for_date).  Existing rows for that date are
   replaced with the freshly-computed roll-up.

   Status rules (configurable in production via a config table — kept inline
   here for clarity):
       absent      first_in IS NULL
       half-day    duration_minutes  < 240
       late        first_in > '10:30'  AND duration_minutes >= 240
       present     otherwise
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE mart.sp_close_attendance_day
    @for_date DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @start DATETIME2(0) = CAST(@for_date AS DATETIME2(0));
        DECLARE @end   DATETIME2(0) = DATEADD(DAY, 1, @start);

        /* Stage per-user roll-up */
        IF OBJECT_ID(N'tempdb..#rollup') IS NOT NULL DROP TABLE #rollup;

        SELECT
            p.user_id,
            MIN(CASE WHEN p.direction = 'IN'  THEN p.punch_at END) AS first_in,
            MAX(CASE WHEN p.direction = 'OUT' THEN p.punch_at END) AS last_out
        INTO #rollup
        FROM core.fact_punch p
        WHERE p.punch_at >= @start AND p.punch_at < @end
        GROUP BY p.user_id;

        /* Compute duration + status */
        IF OBJECT_ID(N'tempdb..#out') IS NOT NULL DROP TABLE #out;
        SELECT
            user_id,
            first_in,
            last_out,
            CASE
                WHEN first_in IS NULL OR last_out IS NULL THEN NULL
                ELSE DATEDIFF(MINUTE, first_in, last_out)
            END AS duration_minutes,
            CASE
                WHEN first_in IS NULL                                      THEN N'absent'
                WHEN DATEDIFF(MINUTE, first_in, ISNULL(last_out, first_in)) < 240 THEN N'half-day'
                WHEN CAST(first_in AS TIME) > '10:30'                      THEN N'late'
                ELSE                                                            N'present'
            END AS status
        INTO #out
        FROM #rollup;

        /* Replace any prior roll-up for this date */
        DELETE FROM mart.fact_daily_attendance WHERE attendance_date = @for_date;

        INSERT INTO mart.fact_daily_attendance
                  (user_id, attendance_date, first_in, last_out, duration_minutes, status)
        SELECT     user_id, @for_date,       first_in, last_out, duration_minutes, status
        FROM       #out;

        /* Absent rows for active users who had no punches */
        INSERT INTO mart.fact_daily_attendance
                  (user_id, attendance_date, status)
        SELECT     u.user_id, @for_date, N'absent'
        FROM       core.dim_user u
        WHERE      u.is_active = 1
          AND      NOT EXISTS (
              SELECT 1 FROM mart.fact_daily_attendance d
              WHERE d.user_id = u.user_id AND d.attendance_date = @for_date
          );

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

PRINT N'mart.sp_close_attendance_day created';
GO
