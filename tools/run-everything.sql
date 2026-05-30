/* =============================================================================
   run-everything.sql
   Single-shot setup script for a fresh install.

   Run this in SSMS / sqlcmd connected to your demo SQL Server instance
   (e.g. LocalDB).  It will:

     1. Create/recreate ERPToolkitDemo database
     2. Apply all schema files in order
     3. Create all stored procedures + functions + views
     4. Seed ~1000 rows of synthetic data
     5. Run a sample close-day + KPI queries

   AFTER this script: optionally install tSQLt (see tools/install-tsqlt.sql)
   and run the test classes.

   Estimated time: < 60 seconds on LocalDB.
   ============================================================================= */

:on error exit
PRINT N'Note: run this with sqlcmd, or copy the :r lines into SSMS via SQLCMD Mode.';
GO

-- 1. Schema
:r ..\schema\000-setup-database.sql
:r ..\schema\001-core-schema.sql
:r ..\schema\002-import-log.sql
:r ..\schema\003-audit-framework.sql
:r ..\schema\004-scd2-dimensions.sql

-- 2. Procedures
:r ..\procedures\imports\sp_import_attendance.sql
:r ..\procedures\imports\sp_close_attendance_day.sql
:r ..\procedures\scd2\sp_merge_dim_student.sql
:r ..\procedures\analytics\sp_kpi_absenteeism.sql
:r ..\procedures\analytics\sp_kpi_collection_rate.sql
:r ..\procedures\maintenance\sp_index_health.sql
:r ..\procedures\maintenance\sp_reindex_smart.sql
:r ..\procedures\maintenance\sp_missing_indexes.sql
:r ..\procedures\maintenance\sp_unused_indexes.sql
:r ..\procedures\dq\sp_find_orphans.sql
:r ..\procedures\dq\sp_find_duplicates.sql

-- 3. Functions
:r ..\functions\fn_business_days_between.sql
:r ..\functions\fn_age_in_years.sql
:r ..\functions\fn_split_csv.sql
:r ..\functions\fn_date_range.sql

-- 4. Views
:r ..\views\vw_attendance_daily.sql
:r ..\views\vw_finance_summary.sql

-- 5. Seed
:r ..\samples\seed-small.sql

-- 6. Sample: close a day + KPI
EXEC mart.sp_close_attendance_day @for_date = '2026-04-15';

SELECT TOP 10 * FROM mart.vw_attendance_daily WHERE attendance_date = '2026-04-15';

EXEC mart.sp_kpi_absenteeism      @from_date = '2026-04-01', @to_date = '2026-04-30';
EXEC mart.sp_kpi_collection_rate  @from_date = '2026-04-01', @to_date = '2026-04-30';

PRINT N'================================================================';
PRINT N' ERPToolkitDemo ready.  Inspect the results above.';
PRINT N'================================================================';
GO
