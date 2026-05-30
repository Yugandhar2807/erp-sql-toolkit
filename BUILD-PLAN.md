# Showcase Project 03 — `erp-sql-toolkit`

> A curated, tested, source-controlled T-SQL toolkit covering the patterns most enterprise ERP systems need.

---

## One-liner

The T-SQL patterns I use day-to-day, refactored into a clean-room toolkit: idempotent imports, audit triggers, SCD Type 2, performance helpers, data-quality checks. Every script tested with tSQLt.

---

## Why this project (recruiter angle)

- Pure SQL signals **data engineering depth** — most freshers can't write a non-trivial SP
- "tSQLt unit tests" is a phrase that makes senior data engineers nod
- Idempotency, audit, SCD — these are the *boring* enterprise patterns that prove production experience
- Different artifact type from #1 and #2 — diversifies your portfolio

---

## Modules included

### 1. Idempotent imports — `procedures/imports/`

The single most valuable pattern. Most import SPs in the wild re-insert on re-run; yours won't.

```
procedures/imports/
├── sp_import_attendance.sql       # stage → merge → audit → log
├── sp_import_marks.sql            # with duplicate detection
├── sp_import_payments.sql         # with reversal handling
└── _shared/
    ├── sp_import_log_start.sql
    ├── sp_import_log_finish.sql
    └── tbl_import_log.sql
```

Each SP is **safe to run any number of times with the same `@batch_id`** — no duplicates, no data loss.

### 2. SCD Type 2 — `procedures/scd2/`

Slowly-changing dimensions with effective dating. The pattern works for student, program, instructor, course tables.

### 3. Audit triggers — `triggers/`

One trigger template you configure per-table; logs every INSERT/UPDATE/DELETE to a central audit table with the user, timestamp, and before/after JSON.

### 4. Performance helpers — `procedures/maintenance/`

```
procedures/maintenance/
├── sp_index_health.sql            # fragmentation report
├── sp_reindex_smart.sql           # online reorganize/rebuild as appropriate
├── sp_missing_indexes.sql         # missing-index report with size estimate
├── sp_unused_indexes.sql          # candidates to drop
└── sp_top_queries.sql             # top-N queries by CPU / reads
```

### 5. Data quality — `procedures/dq/`

```
procedures/dq/
├── sp_find_orphans.sql            # rows with broken FKs (incl. unenforced)
├── sp_find_duplicates.sql         # configurable key-set duplicates
├── sp_check_referential.sql       # schema-wide referential integrity
└── sp_drift_report.sql            # compare schema A vs schema B
```

### 6. Test suite — `tests/`

Full tSQLt coverage. Tests run in ~3 seconds.

---

## Featured pattern — the idempotent import (the readme highlight)

```sql
CREATE OR ALTER PROCEDURE sp_import_attendance
    @batch_id    NVARCHAR(64),
    @source_file NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @log_id BIGINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Start audit row (returns log_id)
        EXEC sp_import_log_start
            @batch_id   = @batch_id,
            @operation  = N'IMPORT_ATTENDANCE',
            @source     = @source_file,
            @log_id     = @log_id OUTPUT;

        -- 2) Idempotency guard: if this batch has already completed, exit clean
        IF EXISTS (
            SELECT 1 FROM import_log
            WHERE batch_id = @batch_id
              AND operation = N'IMPORT_ATTENDANCE'
              AND status = N'COMPLETED'
              AND log_id <> @log_id
        )
        BEGIN
            EXEC sp_import_log_finish
                @log_id = @log_id,
                @status = N'SKIPPED_IDEMPOTENT';
            COMMIT;
            RETURN;
        END

        -- 3) Stage (assumes data already in stg_punch_raw via BULK INSERT)
        --    Real-world: this SP is called after staging finishes.

        -- 4) Merge with hash-based change detection
        ;WITH src AS (
            SELECT
                s.user_external_ref,
                s.punch_at,
                s.device_id,
                s.direction,
                HASHBYTES('SHA2_256',
                    CONCAT_WS('|', s.user_external_ref, s.punch_at, s.device_id, s.direction)
                ) AS row_hash
            FROM stg_punch_raw s
            WHERE s.batch_id = @batch_id
        )
        MERGE fact_punch AS tgt
        USING src
            ON tgt.user_external_ref = src.user_external_ref
           AND tgt.punch_at         = src.punch_at
           AND tgt.device_id        = src.device_id
        WHEN NOT MATCHED THEN
            INSERT (user_external_ref, punch_at, device_id, direction, row_hash, batch_id)
            VALUES (src.user_external_ref, src.punch_at, src.device_id, src.direction, src.row_hash, @batch_id);

        -- 5) Finish audit row
        DECLARE @rows INT = @@ROWCOUNT;
        EXEC sp_import_log_finish
            @log_id       = @log_id,
            @status       = N'COMPLETED',
            @rows_affected = @rows;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC sp_import_log_finish
            @log_id  = @log_id,
            @status  = N'FAILED',
            @error   = ERROR_MESSAGE();
        THROW;
    END CATCH
END
GO
```

Tested with `tests/test_import_attendance.sql` — six test cases:
- Empty staging → no rows inserted
- Fresh batch → all rows inserted
- Re-run same batch_id → zero new rows (idempotent)
- Re-run after partial fail → completes the unfinished batch
- Bad data in staging → transaction rolls back, audit row marks FAILED
- Concurrent runs with different batch_ids → both succeed without interference

---

## Folder structure

```
erp-sql-toolkit/
├── schema/                           # versioned DDL, run in order
│   ├── 001-core-schema.sql
│   ├── 002-import-log.sql
│   ├── 003-audit-framework.sql
│   └── 004-scd2-dimensions.sql
├── procedures/
│   ├── imports/
│   ├── scd2/
│   ├── analytics/
│   ├── maintenance/
│   ├── dq/
│   └── utilities/
├── functions/
│   ├── scalar/
│   │   ├── fn_business_days_between.sql
│   │   └── fn_age_in_years.sql
│   └── table-valued/
│       ├── fn_split_csv.sql
│       └── fn_date_range.sql
├── views/
│   ├── vw_attendance_daily.sql
│   └── vw_dq_orphans.sql
├── triggers/
│   ├── trg_audit_generic.sql
│   └── _generator/
│       └── generate_audit_trigger.sql   # generates trigger DDL for any table
├── tests/                            # tSQLt
│   ├── test_imports.sql
│   ├── test_scd2.sql
│   ├── test_audit.sql
│   └── test_dq.sql
├── samples/
│   ├── seed-small.sql                # 1k rows for smoke testing
│   └── seed-large.sql                # 1M rows for perf testing
├── tools/
│   ├── install-tsqlt.sql
│   └── run-all-tests.sql
├── docs/
│   ├── conventions.md
│   ├── idempotency-pattern.md
│   ├── audit-pattern.md
│   ├── scd2-pattern.md
│   ├── performance-patterns.md
│   └── img/
└── README.md
```

---

## Build plan (1 weekend)

### Day 1
- [ ] Schema files (4 files)
- [ ] One full import SP with audit + idempotency
- [ ] tSQLt setup + first 3 tests passing
- [ ] Seed scripts

### Day 2
- [ ] SCD2 SP
- [ ] Audit trigger generator
- [ ] All 5 perf helpers (mostly copy from public Microsoft Tiger Toolbox patterns, with your improvements)
- [ ] DQ procedures
- [ ] README + docs

---

## Interview hook

"I have a SQL toolkit on GitHub — it's the patterns I use daily but rebuilt clean-room. The piece I'd point you to is the import-with-idempotency pattern. The standard `MERGE` has a known race condition; mine wraps it correctly with `HOLDLOCK` and a batch-level idempotency check, and the tSQLt suite has the case for it."

That sentence is the entire reason this repo exists.
