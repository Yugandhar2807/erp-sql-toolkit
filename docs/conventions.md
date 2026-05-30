# T-SQL Conventions used in this toolkit

These are the conventions every script in this repo follows. They're picked for
*readability and safety*, not personal taste — each one prevents a specific
class of production bug.

## Naming
- `snake_case` everywhere (tables, columns, procs, functions).
  → Avoids quoting; consistent with ANSI / Postgres / Snowflake.
- Tables: singular (`dim_user`, not `dim_users`) — Kimball convention.
- Stored procedures: `sp_<verb>_<thing>` (`sp_import_attendance`).
  → Yes, `sp_` is fine in user schemas; the perf myth applies only to `dbo.sp_*`.
- Indexes: `ix_<table>_<columns>` for nonclustered, `uq_<table>_<columns>` for unique.
- Foreign keys: never named `FK__...__...auto`; use `fk_<table>_<refTable>`.

## Schemas (purpose-of-data, not technology)
- `core`  — durable business entities (dims & facts)
- `stg`   — staging tables for imports
- `audit` — audit log & import log
- `mart`  — analytical marts / roll-ups / KPI procs
- `util`  — utility functions & maintenance procs
- `dq`    — data-quality procs
- `dbo`   — left empty (anti-pattern bait)

## Every stored procedure starts with
```sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
```
Why:
- `NOCOUNT ON` — fewer roundtrips, cleaner client output.
- `XACT_ABORT ON` — any error in a transaction causes the whole batch to roll back,
  not just the current statement. Closes a whole class of "partial commit" bugs.

## Every write happens inside `BEGIN TRY ... BEGIN CATCH ... ROLLBACK ... THROW`
Never swallow an exception. Always rethrow so the caller knows.

## Every table has
- `created_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()`
- `updated_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()`
- A primary key (audit triggers require one)

## Never do
- `SELECT *` in production code (schema drift breaks the consumer)
- String-concat to build SQL — always `sp_executesql` with parameters
- `MERGE` without `HOLDLOCK` on the source CTE — the classic race
- `DATETIME` — always `DATETIME2(0)` (smaller, more accurate, ANSI)
- Implicit conversions — they tank query plans

## Always do
- `SET NOCOUNT ON` first line of every proc
- Idempotency: any procedure that can be retried should be safe to retry
- Audit-friendly: write to `audit.import_log` before and after every meaningful change
- Parameter validation at the boundary — raise early
- Comments only when *why* is not obvious from the code

## Index philosophy
- Cover the predicate columns (composite index)
- INCLUDE the SELECT-list columns that aren't filter columns
- Don't index columns with very low cardinality unless filtered to a small subset
- Drop indexes that have zero reads in `sys.dm_db_index_usage_stats` over a long observation window
