# Slowly Changing Dimension Type 2

What we use it for: tracking the history of a dimension — for example a
student's program / section / batch — so that historical facts continue to
attribute correctly even after the dimension changes.

## The shape

For every natural key (`external_ref`), the table has 1..N rows:

| student_sk | external_ref | full_name | program | section | effective_from | effective_to | is_current | version_no |
|-----------:|--------------|-----------|---------|---------|----------------|--------------|------------|------------|
| 14         | S001         | Alice     | BTC     | A       | 2026-01-01     | 2026-03-31   | 0          | 1          |
| 27         | S001         | Alice     | BTC     | B       | 2026-04-01     | 9999-12-31   | 1          | 2          |

The current row has `effective_to = '9999-12-31'` and `is_current = 1`.
There is a **filtered unique index** on `(external_ref) WHERE is_current = 1`
to make "current row" lookups O(1).

## Three categories of input

1. **Brand-new natural key** → insert v1, is_current = 1, effective_from = caller-supplied
2. **Unchanged snapshot** → no-op (compared via SHA2_256 row hash)
3. **Changed snapshot** → expire current (effective_to, is_current = 0), insert new version

## Late-arriving rows

Common in real ERP: someone corrects a historical record. The toolkit handles
this in `core.sp_merge_dim_student` step 3:

```text
Existing versions:
   v1 (effective_from 2026-01-01, is_current=0, to=2026-03-31)
   v2 (effective_from 2026-04-01, is_current=1, to=9999-12-31)

Late-arriving row:
   effective_from 2026-02-15

Result:
   v1 unchanged (effective_from 2026-01-01..2026-02-14)
   late row inserted (effective_from 2026-02-15..2026-03-31, is_current=0)
   v2 unchanged
```

The late row's `effective_to` is set to `next_effective_from - 1 day`, preserving
the contiguous timeline.

## Why a row hash?

Without one, every snapshot looks "different" because at the very least the
ingest timestamp varies. With `HASHBYTES('SHA2_256', concat_ws(...))`, we
compare only the *business attributes* and skip no-op merges entirely. This is
the difference between an SCD2 SP that runs in 80ms and one that takes 4s.
