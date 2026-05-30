# The Idempotency Pattern

Most enterprise SQL imports have a hidden bug: re-running them inserts duplicates.
The pattern below is what we use to make every `core.sp_import_*` procedure
**safe to re-run any number of times with the same `@batch_id`**.

## The shape

```text
   Caller                          DB
     │                              │
     │  BULK INSERT into stg ──────▶│  (rows tagged with @batch_id)
     │  EXEC sp_import_X ──────────▶│
     │                              │  1. Write audit row "RUNNING"
     │                              │  2. Idempotency guard:
     │                              │       has batch_id+operation already COMPLETED ?
     │                              │       YES → return SKIPPED_IDEMPOTENT
     │                              │  3. Merge stg → fact using a uniqueness key
     │                              │  4. Audit row "COMPLETED" + rows_affected
     │  ◀──────────────────────────  │
```

## The three things that make this safe

### 1. A `batch_id` from the caller, not the DB
The caller decides what "this batch" means. The DB does not invent a batch_id —
that would break re-run semantics (a second call would get a *different* batch_id
and import everything again).

### 2. A uniqueness key the DB enforces
In `core.fact_punch` we use `(user_id, punch_at, device_id, direction)` as the
unique tuple. The import does `INSERT ... WHERE NOT EXISTS`. Duplicates are
**physically impossible** because the DB also has a unique index — even a buggy
caller cannot insert them.

### 3. An audit row before and after
`audit.import_log` has a row per attempt. The `(batch_id, operation, status)`
triplet is the source of truth for "was this batch completed."

## Why `MERGE` with `HOLDLOCK`?

The canonical `MERGE` statement has a race condition: two concurrent runs
both see "row doesn't exist" and both try to `INSERT`, deadlocking or violating
the unique index. The fix is `WITH (HOLDLOCK)` on the source CTE, plus the
`SET XACT_ABORT ON` we already have.

In this toolkit we go one step further and use `INSERT ... WHERE NOT EXISTS`
inside `SET XACT_ABORT ON` with the unique index as the safety net. Same effect,
slightly easier to read.

## Interview talking point

> *"My imports are idempotent by design. The `batch_id` is caller-supplied,
> the uniqueness key is enforced by the DB, the audit log records every attempt.
> If someone re-runs an import — even halfway through a transient failure — they
> get exactly the rows they expect, no duplicates, with a clear audit trail."*

That sentence is the entire reason this pattern exists.
