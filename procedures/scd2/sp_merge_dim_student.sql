/* =============================================================================
   sp_merge_dim_student.sql

   SCD Type 2 merge for core.dim_student_scd2.

   Input: a JSON array of student snapshots (external_ref, full_name,
   program_code, section, effective_from).

   Rules:
     - If external_ref does not exist  → insert v1, is_current = 1
     - If snapshot row_hash matches the current row → no-op
     - If row_hash differs              → expire current (set effective_to and
                                          is_current=0), insert new version
     - Late-arriving rows (effective_from earlier than the current row's
       effective_from) are inserted with an end-date equal to the next-newer
       version's effective_from − 1 day.  This preserves history.

   row_hash = SHA2_256(full_name | program_code | section)
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE core.sp_merge_dim_student
    @snapshots NVARCHAR(MAX)                                   -- JSON array
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Parse JSON into a stable temp set with computed row_hash */
        IF OBJECT_ID(N'tempdb..#src') IS NOT NULL DROP TABLE #src;

        SELECT
            j.external_ref,
            j.full_name,
            j.program_code,
            j.section,
            j.effective_from,
            HASHBYTES('SHA2_256',
                CONCAT_WS(N'|', j.full_name, j.program_code, ISNULL(j.section, N''))
            ) AS row_hash
        INTO #src
        FROM OPENJSON(@snapshots)
        WITH (
            external_ref   NVARCHAR(64)  '$.external_ref',
            full_name      NVARCHAR(200) '$.full_name',
            program_code   NVARCHAR(20)  '$.program_code',
            section        NVARCHAR(20)  '$.section',
            effective_from DATE          '$.effective_from'
        ) j;

        /* 1. Brand-new natural keys → insert v1 */
        INSERT INTO core.dim_student_scd2
              (external_ref, full_name, program_code, section,
               effective_from, effective_to, is_current, version_no, row_hash)
        SELECT s.external_ref, s.full_name, s.program_code, s.section,
               s.effective_from, '9999-12-31', 1, 1, s.row_hash
        FROM   #src s
        WHERE  NOT EXISTS (
            SELECT 1 FROM core.dim_student_scd2 d
            WHERE d.external_ref = s.external_ref
        );

        /* 2. Existing keys with CHANGED row_hash AND effective_from >= current effective_from
              → expire current, insert new version */
        IF OBJECT_ID(N'tempdb..#changes') IS NOT NULL DROP TABLE #changes;

        SELECT
            s.external_ref,
            s.full_name,
            s.program_code,
            s.section,
            s.effective_from,
            s.row_hash,
            cur.student_sk    AS prior_sk,
            cur.version_no    AS prior_version
        INTO #changes
        FROM #src s
        JOIN core.dim_student_scd2 cur
            ON cur.external_ref = s.external_ref AND cur.is_current = 1
        WHERE cur.row_hash <> s.row_hash
          AND s.effective_from >= cur.effective_from;

        UPDATE d
        SET    is_current   = 0,
               effective_to = DATEADD(DAY, -1, c.effective_from)
        FROM   core.dim_student_scd2 d
        JOIN   #changes c ON c.prior_sk = d.student_sk;

        INSERT INTO core.dim_student_scd2
              (external_ref, full_name, program_code, section,
               effective_from, effective_to, is_current, version_no, row_hash)
        SELECT external_ref, full_name, program_code, section,
               effective_from, '9999-12-31', 1, prior_version + 1, row_hash
        FROM   #changes;

        /* 3. Late-arriving rows: effective_from earlier than any existing version's
              effective_from.  Insert with end-date = next version's start - 1 day. */
        IF OBJECT_ID(N'tempdb..#late') IS NOT NULL DROP TABLE #late;

        SELECT
            s.external_ref,
            s.full_name,
            s.program_code,
            s.section,
            s.effective_from,
            s.row_hash,
            (SELECT MIN(d.effective_from)
             FROM   core.dim_student_scd2 d
             WHERE  d.external_ref   = s.external_ref
               AND  d.effective_from > s.effective_from) AS next_effective_from
        INTO #late
        FROM #src s
        WHERE EXISTS (
              SELECT 1 FROM core.dim_student_scd2 d
              WHERE d.external_ref = s.external_ref
                AND d.effective_from > s.effective_from
          )
          AND NOT EXISTS (
              SELECT 1 FROM core.dim_student_scd2 d
              WHERE d.external_ref   = s.external_ref
                AND d.effective_from = s.effective_from
          );

        INSERT INTO core.dim_student_scd2
              (external_ref, full_name, program_code, section,
               effective_from, effective_to, is_current, version_no, row_hash)
        SELECT external_ref, full_name, program_code, section,
               effective_from,
               DATEADD(DAY, -1, next_effective_from),
               0,
               (SELECT ISNULL(MAX(version_no), 0) + 1
                FROM   core.dim_student_scd2 dd
                WHERE  dd.external_ref = l.external_ref),
               row_hash
        FROM   #late l;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

PRINT N'core.sp_merge_dim_student created';
GO
