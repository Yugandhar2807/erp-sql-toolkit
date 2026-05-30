/* =============================================================================
   test_dq.sql
   tSQLt tests for dq.sp_find_orphans and dq.sp_find_duplicates.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF SCHEMA_ID(N'dq_tests') IS NULL EXEC(N'CREATE SCHEMA dq_tests AUTHORIZATION dbo;');
GO
EXEC tSQLt.NewTestClass 'dq_tests';
GO

CREATE OR ALTER PROCEDURE dq_tests.[test find duplicates returns groups with count gt 1]
AS
BEGIN
    EXEC tSQLt.FakeTable @TableName = N'core.dim_user';
    INSERT INTO core.dim_user (user_id, external_ref, full_name, role, joined_on, email)
    VALUES (1, N'A', N'X', N'student', '2026-01-01', N'dup@x.com'),
           (2, N'B', N'Y', N'student', '2026-01-01', N'dup@x.com'),
           (3, N'C', N'Z', N'student', '2026-01-01', N'unique@x.com');

    IF OBJECT_ID(N'tempdb..#captured') IS NOT NULL DROP TABLE #captured;
    CREATE TABLE #captured(email NVARCHAR(200), dup_count INT);

    INSERT INTO #captured
    EXEC dq.sp_find_duplicates @table_schema = N'core', @table_name = N'dim_user', @key_cols = N'email';

    SELECT email = N'dup@x.com', dup_count = 2 INTO #expected;
    SELECT email, dup_count INTO #actual FROM #captured;

    EXEC tSQLt.AssertEqualsTable '#expected', '#actual';
END
GO

PRINT N'dq_tests test class created -- run with: EXEC tSQLt.Run ''dq_tests'';';
GO
