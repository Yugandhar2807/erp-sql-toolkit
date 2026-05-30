/* =============================================================================
   test_scd2.sql
   tSQLt unit tests for core.sp_merge_dim_student.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'scd2_tests') IS NULL EXEC(N'CREATE SCHEMA scd2_tests AUTHORIZATION dbo;');
GO
EXEC tSQLt.NewTestClass 'scd2_tests';
GO

CREATE OR ALTER PROCEDURE scd2_tests.[test brand-new student inserts v1 as current]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.dim_student_scd2';

    EXEC core.sp_merge_dim_student
         @snapshots = N'[{"external_ref":"S1","full_name":"Alice","program_code":"BTC","section":"A","effective_from":"2026-01-01"}]';

    SELECT external_ref = N'S1', version_no = 1, is_current = CAST(1 AS BIT)
    INTO   #expected;

    SELECT external_ref, version_no, is_current
    INTO   #actual
    FROM   core.dim_student_scd2;

    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

CREATE OR ALTER PROCEDURE scd2_tests.[test unchanged snapshot is no-op]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.dim_student_scd2';

    EXEC core.sp_merge_dim_student
         @snapshots = N'[{"external_ref":"S1","full_name":"Alice","program_code":"BTC","section":"A","effective_from":"2026-01-01"}]';

    -- Same snapshot again
    EXEC core.sp_merge_dim_student
         @snapshots = N'[{"external_ref":"S1","full_name":"Alice","program_code":"BTC","section":"A","effective_from":"2026-01-01"}]';

    SELECT row_count = 1 INTO #expected;
    SELECT row_count = COUNT(*) INTO #actual FROM core.dim_student_scd2;

    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

CREATE OR ALTER PROCEDURE scd2_tests.[test section change creates v2 and expires v1]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.dim_student_scd2';

    EXEC core.sp_merge_dim_student
         @snapshots = N'[{"external_ref":"S1","full_name":"Alice","program_code":"BTC","section":"A","effective_from":"2026-01-01"}]';

    -- New section from 2026-04-01
    EXEC core.sp_merge_dim_student
         @snapshots = N'[{"external_ref":"S1","full_name":"Alice","program_code":"BTC","section":"B","effective_from":"2026-04-01"}]';

    DECLARE @v1_current BIT = (SELECT is_current FROM core.dim_student_scd2 WHERE version_no = 1);
    DECLARE @v2_current BIT = (SELECT is_current FROM core.dim_student_scd2 WHERE version_no = 2);
    DECLARE @v1_to     DATE = (SELECT effective_to FROM core.dim_student_scd2 WHERE version_no = 1);

    EXEC tSQLt.AssertEquals @Expected = 0,            @Actual = @v1_current,
        @Message = N'v1 should no longer be current';
    EXEC tSQLt.AssertEquals @Expected = 1,            @Actual = @v2_current,
        @Message = N'v2 should be current';
    EXEC tSQLt.AssertEquals @Expected = '2026-03-31', @Actual = @v1_to,
        @Message = N'v1 effective_to should be one day before v2 effective_from';
END
GO

PRINT N'scd2_tests test class created -- run with: EXEC tSQLt.Run ''scd2_tests'';';
GO
