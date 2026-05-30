/* =============================================================================
   004-scd2-dimensions.sql
   Slowly-Changing-Dimension Type 2 table for student-program history.
   Pattern: surrogate key + (effective_from, effective_to, is_current).
   Late-arriving changes are handled in scd2.sp_merge_dim_student.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'core.dim_student_scd2', N'U') IS NOT NULL DROP TABLE core.dim_student_scd2;
GO
CREATE TABLE core.dim_student_scd2
(
    student_sk        BIGINT IDENTITY(1,1) PRIMARY KEY,
    external_ref      NVARCHAR(64)  NOT NULL,
    full_name         NVARCHAR(200) NOT NULL,
    program_code      NVARCHAR(20)  NOT NULL,
    section           NVARCHAR(20)  NULL,
    effective_from    DATE          NOT NULL,
    effective_to      DATE          NOT NULL,                   -- inclusive sentinel '9999-12-31' for current row
    is_current        BIT           NOT NULL,
    version_no        INT           NOT NULL,
    row_hash          BINARY(32)    NOT NULL,                   -- SHA2_256(full_name|program|section) — detect change
    valid_from_dt     DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- One current row per natural key
CREATE UNIQUE INDEX uq_dim_student_scd2_current
    ON core.dim_student_scd2(external_ref)
    WHERE is_current = 1;

-- Lookups by natural key + version for history queries
CREATE INDEX ix_dim_student_scd2_ref_version
    ON core.dim_student_scd2(external_ref, version_no);

-- Point-in-time lookup
CREATE INDEX ix_dim_student_scd2_effective
    ON core.dim_student_scd2(external_ref, effective_from, effective_to)
    INCLUDE (program_code, section);
GO

PRINT N'core.dim_student_scd2 created with SCD2 indexes';
GO
