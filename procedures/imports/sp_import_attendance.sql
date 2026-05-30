/* =============================================================================
   sp_import_attendance.sql

   The flagship idempotent-import pattern.

   Lifecycle:
     1. Caller bulk-loads rows into stg.punch_raw with a unique @batch_id
     2. Caller invokes core.sp_import_attendance @batch_id
     3. Procedure:
        a. Writes a 'RUNNING' row to audit.import_log
        b. Idempotency guard: if this batch already COMPLETED, returns immediately
        c. Merges staging → core.fact_punch using SHA2_256 row hash for dedup
        d. Marks audit row COMPLETED with @@ROWCOUNT, or FAILED with error

   Re-running with the same @batch_id is SAFE — yields zero new rows.

   Why HOLDLOCK on the source CTE?  Closes the canonical MERGE race condition
   where two concurrent runs both see "row doesn't exist" and both insert.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE core.sp_import_attendance
    @batch_id     NVARCHAR(64),
    @source_file  NVARCHAR(400) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @log_id BIGINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* 1. Start audit row */
        EXEC audit.sp_import_log_start
            @batch_id   = @batch_id,
            @operation  = N'IMPORT_ATTENDANCE',
            @source     = @source_file,
            @log_id     = @log_id OUTPUT;

        /* 2. Idempotency guard: was this batch already completed by an earlier run? */
        IF EXISTS (
            SELECT 1
            FROM   audit.import_log
            WHERE  batch_id  = @batch_id
              AND  operation = N'IMPORT_ATTENDANCE'
              AND  status    = N'COMPLETED'
              AND  log_id   <> @log_id
        )
        BEGIN
            EXEC audit.sp_import_log_finish
                @log_id = @log_id,
                @status = N'SKIPPED_IDEMPOTENT';
            COMMIT;
            RETURN 0;
        END

        /* 3. Validate staging has rows for this batch */
        IF NOT EXISTS (SELECT 1 FROM stg.punch_raw WHERE batch_id = @batch_id)
        BEGIN
            EXEC audit.sp_import_log_finish
                @log_id        = @log_id,
                @status        = N'COMPLETED',
                @rows_affected = 0;
            COMMIT;
            RETURN 0;
        END

        /* 4. Resolve user_external_ref → user_id and pre-hash each candidate row.
              Materialize to a temp table so the MERGE source is stable. */
        IF OBJECT_ID(N'tempdb..#src') IS NOT NULL DROP TABLE #src;

        SELECT
            u.user_id,
            s.punch_at,
            s.device_id,
            UPPER(LTRIM(RTRIM(s.direction))) AS direction,
            HASHBYTES('SHA2_256',
                CONCAT_WS(N'|',
                    CAST(u.user_id AS NVARCHAR(20)),
                    CONVERT(NVARCHAR(40), s.punch_at, 121),
                    s.device_id,
                    UPPER(LTRIM(RTRIM(s.direction)))
                )
            ) AS row_hash
        INTO #src
        FROM   stg.punch_raw s WITH (HOLDLOCK)
        JOIN   core.dim_user u
               ON u.external_ref = s.user_external_ref
        WHERE  s.batch_id = @batch_id
          AND  UPPER(LTRIM(RTRIM(s.direction))) IN (N'IN', N'OUT');

        /* 5. Insert only rows whose (user, punch_at, device, direction) does not yet exist.
              fact_punch has a unique index on those four columns. */
        DECLARE @inserted INT;

        INSERT INTO core.fact_punch
                  (user_id, punch_at, device_id, direction, row_hash, batch_id)
        SELECT     src.user_id, src.punch_at, src.device_id, src.direction, src.row_hash, @batch_id
        FROM       #src AS src
        WHERE NOT EXISTS (
            SELECT 1
            FROM   core.fact_punch f
            WHERE  f.user_id   = src.user_id
              AND  f.punch_at  = src.punch_at
              AND  f.device_id = src.device_id
              AND  f.direction = src.direction
        );

        SET @inserted = @@ROWCOUNT;

        /* 6. Finish audit row */
        EXEC audit.sp_import_log_finish
            @log_id        = @log_id,
            @status        = N'COMPLETED',
            @rows_affected = @inserted;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        DECLARE @err NVARCHAR(2000) = LEFT(ERROR_MESSAGE(), 2000);
        IF @log_id IS NOT NULL
            EXEC audit.sp_import_log_finish
                @log_id = @log_id,
                @status = N'FAILED',
                @error  = @err;

        THROW;
    END CATCH
END
GO

PRINT N'core.sp_import_attendance created';
GO
