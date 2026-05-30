/* =============================================================================
   002-import-log.sql
   The audit table every idempotent import procedure writes to.
   Track: who ran what, when, with which batch_id, succeeded or failed, how many rows.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'audit.import_log', N'U') IS NOT NULL DROP TABLE audit.import_log;
GO
CREATE TABLE audit.import_log
(
    log_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id          NVARCHAR(64)   NOT NULL,
    operation         NVARCHAR(80)   NOT NULL,                  -- e.g. 'IMPORT_ATTENDANCE'
    source            NVARCHAR(400)  NULL,                      -- file name, source system tag, etc.
    started_at        DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    finished_at       DATETIME2(0)   NULL,
    status            NVARCHAR(30)   NOT NULL DEFAULT N'RUNNING',
                                                                 -- RUNNING | COMPLETED | SKIPPED_IDEMPOTENT | FAILED
    rows_affected     INT            NULL,
    error_message     NVARCHAR(2000) NULL,
    executed_by       NVARCHAR(128)  NOT NULL DEFAULT SUSER_SNAME()
);
GO

CREATE INDEX ix_import_log_batch_op
    ON audit.import_log(batch_id, operation, status);

CREATE INDEX ix_import_log_started
    ON audit.import_log(started_at DESC) INCLUDE(operation, status);
GO

PRINT N'audit.import_log created';
GO

/* ---------- sp_import_log_start ------------------------------------------- */
CREATE OR ALTER PROCEDURE audit.sp_import_log_start
    @batch_id   NVARCHAR(64),
    @operation  NVARCHAR(80),
    @source     NVARCHAR(400) = NULL,
    @log_id     BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.import_log (batch_id, operation, source, status)
    VALUES (@batch_id, @operation, @source, N'RUNNING');

    SET @log_id = SCOPE_IDENTITY();
END
GO

/* ---------- sp_import_log_finish ------------------------------------------ */
CREATE OR ALTER PROCEDURE audit.sp_import_log_finish
    @log_id         BIGINT,
    @status         NVARCHAR(30),                               -- COMPLETED | SKIPPED_IDEMPOTENT | FAILED
    @rows_affected  INT            = NULL,
    @error          NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE audit.import_log
    SET    finished_at   = SYSUTCDATETIME(),
           status        = @status,
           rows_affected = @rows_affected,
           error_message = @error
    WHERE  log_id = @log_id;
END
GO

PRINT N'audit.sp_import_log_start / sp_import_log_finish created';
GO
