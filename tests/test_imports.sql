/* =============================================================================
   test_imports.sql
   tSQLt unit tests for core.sp_import_attendance.

   Prereq: install tSQLt first.  See tools/install-tsqlt.sql.
   Run: EXEC tSQLt.Run 'imports';
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'imports') IS NULL EXEC(N'CREATE SCHEMA imports AUTHORIZATION dbo;');
GO
EXEC tSQLt.NewTestClass 'imports';
GO

/* ---------------------------------------------------------------------------
   Fixture: one user, no existing punches, one staged event for batch 'B1'
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE imports.[test fresh batch inserts all staged rows]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.fact_punch';
    EXEC tSQLt.FakeTable @TableName = N'core.dim_user';
    EXEC tSQLt.FakeTable @TableName = N'stg.punch_raw';
    EXEC tSQLt.FakeTable @TableName = N'audit.import_log';

    INSERT INTO core.dim_user (user_id, external_ref, full_name, role, joined_on, is_active)
    VALUES (1, N'STU001', N'Test User', N'student', '2026-01-01', 1);

    INSERT INTO stg.punch_raw (batch_id, user_external_ref, punch_at, device_id, direction)
    VALUES (N'B1', N'STU001', '2026-05-10 09:00', N'DEV-A', N'IN'),
           (N'B1', N'STU001', '2026-05-10 17:30', N'DEV-A', N'OUT');

    EXEC core.sp_import_attendance @batch_id = N'B1';

    SELECT count_rows = COUNT(*) INTO #actual FROM core.fact_punch;
    SELECT count_rows = 2 INTO #expected;
    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

/* ---------------------------------------------------------------------------
   Idempotency: re-running with the same batch_id inserts ZERO new rows
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE imports.[test re-running same batch is idempotent]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.fact_punch';
    EXEC tSQLt.FakeTable @TableName = N'core.dim_user';
    EXEC tSQLt.FakeTable @TableName = N'stg.punch_raw';
    EXEC tSQLt.FakeTable @TableName = N'audit.import_log';

    INSERT INTO core.dim_user (user_id, external_ref, full_name, role, joined_on, is_active)
    VALUES (1, N'STU001', N'Test User', N'student', '2026-01-01', 1);

    INSERT INTO stg.punch_raw (batch_id, user_external_ref, punch_at, device_id, direction)
    VALUES (N'B1', N'STU001', '2026-05-10 09:00', N'DEV-A', N'IN');

    EXEC core.sp_import_attendance @batch_id = N'B1';
    DECLARE @after_first INT = (SELECT COUNT(*) FROM core.fact_punch);

    EXEC core.sp_import_attendance @batch_id = N'B1';
    DECLARE @after_second INT = (SELECT COUNT(*) FROM core.fact_punch);

    EXEC tSQLt.AssertEquals @Expected = @after_first, @Actual = @after_second,
        @Message = N'Re-running the same batch must not add rows';
END
GO

/* ---------------------------------------------------------------------------
   Direction lowercase / mixed case is normalized to upper
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE imports.[test direction is normalized to upper]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.fact_punch';
    EXEC tSQLt.FakeTable @TableName = N'core.dim_user';
    EXEC tSQLt.FakeTable @TableName = N'stg.punch_raw';
    EXEC tSQLt.FakeTable @TableName = N'audit.import_log';

    INSERT INTO core.dim_user (user_id, external_ref, full_name, role, joined_on, is_active)
    VALUES (1, N'STU001', N'Test User', N'student', '2026-01-01', 1);

    INSERT INTO stg.punch_raw (batch_id, user_external_ref, punch_at, device_id, direction)
    VALUES (N'B1', N'STU001', '2026-05-10 09:00', N'DEV-A', N'in'),
           (N'B1', N'STU001', '2026-05-10 17:30', N'DEV-A', N'Out');

    EXEC core.sp_import_attendance @batch_id = N'B1';

    SELECT count_in  = SUM(CASE WHEN direction = 'IN'  THEN 1 ELSE 0 END),
           count_out = SUM(CASE WHEN direction = 'OUT' THEN 1 ELSE 0 END)
    INTO #actual FROM core.fact_punch;

    SELECT count_in = 1, count_out = 1 INTO #expected;

    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

/* ---------------------------------------------------------------------------
   Audit log row is written with status COMPLETED
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE imports.[test audit log captures COMPLETED]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.fact_punch';
    EXEC tSQLt.FakeTable @TableName = N'core.dim_user';
    EXEC tSQLt.FakeTable @TableName = N'stg.punch_raw';
    EXEC tSQLt.FakeTable @TableName = N'audit.import_log';

    INSERT INTO core.dim_user (user_id, external_ref, full_name, role, joined_on, is_active)
    VALUES (1, N'STU001', N'Test User', N'student', '2026-01-01', 1);

    INSERT INTO stg.punch_raw (batch_id, user_external_ref, punch_at, device_id, direction)
    VALUES (N'B1', N'STU001', '2026-05-10 09:00', N'DEV-A', N'IN');

    EXEC core.sp_import_attendance @batch_id = N'B1';

    SELECT status = N'COMPLETED' INTO #expected;
    SELECT TOP 1 status INTO #actual FROM audit.import_log
        WHERE batch_id = N'B1' AND operation = N'IMPORT_ATTENDANCE'
        ORDER BY log_id DESC;

    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

PRINT N'imports test class created -- run with: EXEC tSQLt.Run ''imports'';';
GO
