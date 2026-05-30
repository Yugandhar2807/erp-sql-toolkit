# erp-sql-toolkit

> Production-pattern T-SQL toolkit: idempotent imports, audit triggers, SCD Type 2, analytics KPIs, maintenance helpers, data-quality checks. Battle-tested patterns from enterprise ERP work, **rebuilt clean-room** on synthetic data.

<p>
  <img src="https://img.shields.io/badge/SQL_Server-2019%2B-CC2927?logo=microsoft-sql-server&logoColor=white" />
  <img src="https://img.shields.io/badge/T--SQL-source--controlled-CC2927" />
  <img src="https://img.shields.io/badge/tested-tSQLt-success" />
  <img src="https://img.shields.io/badge/license-MIT-blue" />
  <img src="https://img.shields.io/github/last-commit/Yugandhar2807/erp-sql-toolkit?color=DC143C" />
</p>

---

## What's in here

| Module | What it gives you | Key file |
|--------|-------------------|----------|
| **Schema** | Core dims & facts (users, programs, attendance, invoices, payments) on a clean star layout | [`schema/001-core-schema.sql`](schema/001-core-schema.sql) |
| **Import log** | Audit table + start/finish procs used by every idempotent import | [`schema/002-import-log.sql`](schema/002-import-log.sql) |
| **Audit framework** | Generic row-level audit table + trigger generator (JSON before/after) | [`schema/003-audit-framework.sql`](schema/003-audit-framework.sql) |
| **SCD2 dimensions** | Slowly-Changing-Dimension Type 2 schema for student history | [`schema/004-scd2-dimensions.sql`](schema/004-scd2-dimensions.sql) |
| **Idempotent imports** | `sp_import_attendance` — re-runnable with same `batch_id`, zero duplicates | [`procedures/imports/sp_import_attendance.sql`](procedures/imports/sp_import_attendance.sql) |
| **Daily close** | Roll-up of raw punches → one row per user-day with status + duration | [`procedures/imports/sp_close_attendance_day.sql`](procedures/imports/sp_close_attendance_day.sql) |
| **SCD2 merge** | Handles brand-new keys, unchanged rows (no-op), changes, late-arriving rows | [`procedures/scd2/sp_merge_dim_student.sql`](procedures/scd2/sp_merge_dim_student.sql) |
| **Analytics KPIs** | Absenteeism, fee collection rate, aging buckets, per-program drill | [`procedures/analytics/`](procedures/analytics) |
| **Maintenance** | Index health, smart reindex, missing-index DMV report, unused-index report | [`procedures/maintenance/`](procedures/maintenance) |
| **Data quality** | Generic orphan finder, generic duplicate finder | [`procedures/dq/`](procedures/dq) |
| **Functions** | `fn_business_days_between`, `fn_age_in_years`, `fn_split_csv`, `fn_date_range` | [`functions/`](functions) |
| **Views** | `vw_attendance_daily`, `vw_finance_summary` — Power BI / Excel friendly | [`views/`](views) |
| **tSQLt tests** | Unit tests for imports, SCD2, DQ | [`tests/`](tests) |
| **Seed data** | ~1000 rows synthetic data — students, punches, invoices | [`samples/seed-small.sql`](samples/seed-small.sql) |
| **Docs** | T-SQL conventions, idempotency pattern, SCD2 pattern | [`docs/`](docs) |

---

## The featured pattern — Idempotent imports

The single most valuable script in this toolkit. Most enterprise import SPs in
the wild have a hidden bug: re-running them inserts duplicates.

```sql
-- Re-runnable.  Same @batch_id = zero new rows.
EXEC core.sp_import_attendance
     @batch_id    = N'BATCH-2026-05-23',
     @source_file = N'punches.csv';
```

The procedure:
1. Writes a `RUNNING` row to `audit.import_log`
2. **Idempotency guard**: if `(batch_id, operation, status=COMPLETED)` already exists → returns `SKIPPED_IDEMPOTENT`
3. Joins staging → users → computes SHA2_256 row hash
4. `INSERT ... WHERE NOT EXISTS` against the unique index on `(user_id, punch_at, device_id, direction)`
5. Marks audit row `COMPLETED` with `@@ROWCOUNT`, or `FAILED` with error + `THROW`

Full story → [`docs/idempotency-pattern.md`](docs/idempotency-pattern.md)

---

## Quick start

### Prerequisites
- SQL Server 2019+ (LocalDB / Express / Developer all work)
- `sqlcmd` on PATH (ships with SQL Server)

### Run the whole thing (one command, ~60 seconds)

```powershell
# From repo root:
cd tools
sqlcmd -S "(localdb)\MSSQLLocalDB" -i run-everything.sql -v ServerType=LocalDB
```

What it does:
1. Drops/creates `ERPToolkitDemo` database
2. Applies all schema scripts in order
3. Creates every proc, function, and view
4. Seeds ~1000 rows of synthetic data
5. Closes a sample day & prints KPIs

### Apply piecemeal (for review)

```bash
sqlcmd -S "(localdb)\MSSQLLocalDB" -i schema/000-setup-database.sql
sqlcmd -S "(localdb)\MSSQLLocalDB" -i schema/001-core-schema.sql
# ...etc — see tools/run-everything.sql for the canonical order
```

### Try the idempotency demo

```sql
USE ERPToolkitDemo;

-- First run inserts rows
EXEC core.sp_import_attendance @batch_id = N'DEMO-1';
SELECT COUNT(*) AS row_count_after_first_run FROM core.fact_punch WHERE batch_id = N'DEMO-1';

-- Second run is a no-op — zero new rows
EXEC core.sp_import_attendance @batch_id = N'DEMO-1';
SELECT COUNT(*) AS row_count_after_second_run FROM core.fact_punch WHERE batch_id = N'DEMO-1';

-- Audit trail
SELECT TOP 5 batch_id, status, rows_affected, started_at, finished_at
FROM   audit.import_log
WHERE  operation = N'IMPORT_ATTENDANCE'
ORDER  BY log_id DESC;
```

### Try the KPI procedures

```sql
USE ERPToolkitDemo;

EXEC mart.sp_close_attendance_day @for_date = '2026-04-15';

EXEC mart.sp_kpi_absenteeism
     @from_date = '2026-04-01',
     @to_date   = '2026-04-30';

EXEC mart.sp_kpi_collection_rate
     @from_date = '2026-04-01',
     @to_date   = '2026-04-30';
```

---

## Run the tests

```sql
-- 1. Install tSQLt manually — see tools/install-tsqlt.sql
-- 2. Then:
USE ERPToolkitDemo;
EXEC tSQLt.Run 'imports';
EXEC tSQLt.Run 'scd2_tests';
EXEC tSQLt.Run 'dq_tests';

-- Or run everything:
EXEC tSQLt.RunAll;
```

---

## Folder structure

```
erp-sql-toolkit/
├── schema/                          # versioned DDL, run in order
│   ├── 000-setup-database.sql       # drop/create ERPToolkitDemo + schemas
│   ├── 001-core-schema.sql          # dims & facts
│   ├── 002-import-log.sql           # audit.import_log + start/finish procs
│   ├── 003-audit-framework.sql      # audit.row_audit + trigger generator
│   └── 004-scd2-dimensions.sql      # SCD Type 2 dimension table
├── procedures/
│   ├── imports/
│   │   ├── sp_import_attendance.sql # the flagship idempotent import
│   │   └── sp_close_attendance_day.sql
│   ├── scd2/
│   │   └── sp_merge_dim_student.sql # SCD2 merge with late-arrival handling
│   ├── analytics/
│   │   ├── sp_kpi_absenteeism.sql
│   │   └── sp_kpi_collection_rate.sql
│   ├── maintenance/
│   │   ├── sp_index_health.sql
│   │   ├── sp_reindex_smart.sql     # online rebuild >30%, reorg 5..30%
│   │   ├── sp_missing_indexes.sql   # DMV-based suggestions
│   │   └── sp_unused_indexes.sql    # candidates to drop
│   └── dq/
│       ├── sp_find_orphans.sql      # generic, works on any (child,parent) pair
│       └── sp_find_duplicates.sql   # generic, works on any column set
├── functions/
│   ├── fn_business_days_between.sql
│   ├── fn_age_in_years.sql
│   ├── fn_split_csv.sql             # inline TVF
│   └── fn_date_range.sql            # inline TVF
├── views/
│   ├── vw_attendance_daily.sql      # Power BI / Excel friendly
│   └── vw_finance_summary.sql
├── tests/                           # tSQLt
│   ├── test_imports.sql
│   ├── test_scd2.sql
│   └── test_dq.sql
├── samples/
│   └── seed-small.sql               # ~1000 rows synthetic
├── tools/
│   ├── install-tsqlt.sql            # instructions only — fetch tSQLt yourself
│   └── run-everything.sql           # single-shot setup
├── docs/
│   ├── conventions.md               # naming + safety conventions used here
│   ├── idempotency-pattern.md       # why & how
│   └── scd2-pattern.md              # SCD2 with late-arrival handling
├── BUILD-PLAN.md                    # the spec this was built from
├── LICENSE
└── README.md
```

---

## Conventions I follow (and why)

| Rule | Why |
|------|-----|
| `snake_case` for all identifiers | ANSI/Postgres compatible; no quoting |
| `core` / `stg` / `audit` / `mart` / `util` / `dq` schemas | Purpose-of-data, not technology |
| Every SP starts with `SET NOCOUNT ON; SET XACT_ABORT ON;` | Fewer roundtrips + safe transactions |
| Every write wrapped in `TRY ... CATCH ... ROLLBACK ... THROW` | Atomic, observable failures |
| `DATETIME2(0)` everywhere, never `DATETIME` | Smaller, more accurate, ANSI |
| No `SELECT *` in production code | Schema-drift safety |
| `INSERT ... WHERE NOT EXISTS` over naive `MERGE` | Avoids the canonical MERGE race |

Full list → [`docs/conventions.md`](docs/conventions.md)

---

## What I learned building this

- **Idempotency must be designed in, not patched on.** The audit row + uniqueness key + `WHERE NOT EXISTS` pattern is short, but every part of it earns its place. Any one of them missing and re-runs misbehave.
- **The `MERGE` race condition** is the most common production bug in T-SQL data engineering. Most teams write `MERGE` without `HOLDLOCK` because the syntax looks complete. It isn't.
- **Row hashes (`HASHBYTES('SHA2_256', concat_ws(...))`) are the difference between an SCD2 merge that's fast and one that's pathological.** Comparing business attributes via hash means no-op merges are a single comparison, not a full row diff.
- **Audit logs that are *also* the idempotency mechanism are double-duty wins.** One write does both jobs.

---

## Roadmap

- [ ] CDC-aware version of `sp_import_attendance` (consume Change Data Capture instead of staging)
- [ ] Always-on / availability-group-aware variants of `sp_reindex_smart`
- [ ] Column-store fact partitioning examples
- [ ] Parameterized data generator (CLI param: `n_users`, `n_days`)
- [ ] PostgreSQL port for the patterns (FOR JSON → JSON_AGG, etc.)

---

## Disclaimer

This is a **clean-room reference implementation**. No code, schema, screenshot,
or data from any employer or client appears in this repository. All data is
synthetic, generated by the included seeder.

---

## License

MIT — see [LICENSE](LICENSE).

---

*Author: [Yugandhar N](https://github.com/Yugandhar2807) — Junior Software Developer, Fresh B.Tech Grad (Apr 2026)*
