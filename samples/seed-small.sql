/* =============================================================================
   seed-small.sql
   Populates ERPToolkitDemo with ~1000 rows for smoke testing.
   Synthetic data only — no real names, no employer data.

   What you get:
     - 5 years of dim_date (2024..2028)
     - 4 programs
     - 200 users (180 students, 15 faculty, 5 staff)
     - 10 public holidays (2026)
     - 30 days of biometric punches (~6000 events) for batch 'SEED-2026-04'
     - 200 invoices, 150 payments
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

/* ---------- dim_date (2024..2028) ----------------------------------------- */
;WITH years AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM years WHERE d < '2028-12-31'
)
INSERT INTO core.dim_date
       (date_id, full_date, day_of_month, day_of_week, day_name,
        week_of_year, month_of_year, month_name, quarter_of_year, year,
        is_weekend, is_business_day)
SELECT YEAR(d)*10000 + MONTH(d)*100 + DAY(d),
       d,
       DAY(d),
       DATEPART(WEEKDAY, d),
       DATENAME(WEEKDAY, d),
       DATEPART(WEEK, d),
       MONTH(d),
       DATENAME(MONTH, d),
       DATEPART(QUARTER, d),
       YEAR(d),
       CASE WHEN DATEPART(WEEKDAY, d) IN (1,7) THEN 1 ELSE 0 END,    -- Sun=1 / Sat=7 on default DATEFIRST
       CASE WHEN DATEPART(WEEKDAY, d) IN (1,7) THEN 0 ELSE 1 END
FROM   years
OPTION (MAXRECURSION 0);
GO

/* ---------- holidays (2026 representative dates) -------------------------- */
INSERT INTO core.holiday (holiday_date, holiday_name)
VALUES
    ('2026-01-26', N'Republic Day'),
    ('2026-03-06', N'Holi'),
    ('2026-04-14', N'Ambedkar Jayanti'),
    ('2026-05-01', N'Labour Day'),
    ('2026-08-15', N'Independence Day'),
    ('2026-10-02', N'Gandhi Jayanti'),
    ('2026-10-21', N'Diwali'),
    ('2026-12-25', N'Christmas'),
    ('2026-03-31', N'Eid'),
    ('2026-11-04', N'Founders Day');
GO

/* ---------- dim_program ---------------------------------------------------- */
INSERT INTO core.dim_program (program_code, program_name, program_type, duration_years)
VALUES
    (N'BTC',  N'B.Tech Computer Science', N'UG', 4),
    (N'BBM',  N'B.B.M. Business Management', N'UG', 3),
    (N'MCA',  N'Master of Computer Applications', N'PG', 2),
    (N'DIP',  N'Diploma in Engineering', N'Diploma', 3);
GO

/* ---------- dim_user (200 synthetic users) -------------------------------- */
;WITH n AS (
    SELECT TOP (200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM   sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO core.dim_user (external_ref, full_name, role, email, phone, program_id, joined_on, is_active)
SELECT
    N'EXT' + RIGHT('00000' + CAST(i AS VARCHAR(5)), 5),
    CASE i % 6
        WHEN 0 THEN N'Aarav Sharma '   + CAST(i AS NVARCHAR)
        WHEN 1 THEN N'Diya Verma '     + CAST(i AS NVARCHAR)
        WHEN 2 THEN N'Rohan Iyer '     + CAST(i AS NVARCHAR)
        WHEN 3 THEN N'Saanvi Reddy '   + CAST(i AS NVARCHAR)
        WHEN 4 THEN N'Vihaan Kapoor '  + CAST(i AS NVARCHAR)
        ELSE        N'Ananya Patel '   + CAST(i AS NVARCHAR)
    END,
    CASE WHEN i <= 180 THEN N'student' WHEN i <= 195 THEN N'faculty' ELSE N'staff' END,
    N'user' + CAST(i AS VARCHAR(5)) + N'@demo.local',
    N'+9170' + RIGHT('00000000' + CAST(ABS(CHECKSUM(NEWID())) % 99999999 AS VARCHAR(8)), 8),
    ((i - 1) % 4) + 1,                                                                          -- spread across programs
    DATEADD(DAY, -((i * 17) % 800), '2026-04-01'),
    1
FROM n;
GO

/* ---------- fact_punch (~6000 events: 30 days x 200 users x ~1 each)
              Real-life two punches per day; here we vary IN/OUT randomly for variety. */
;WITH d AS (
    SELECT full_date
    FROM   core.dim_date
    WHERE  full_date >= '2026-04-01' AND full_date < '2026-05-01'
      AND  is_business_day = 1
)
INSERT INTO core.fact_punch (user_id, punch_at, device_id, direction, row_hash, batch_id)
SELECT
    u.user_id,
    DATEADD(MINUTE,
        540 + ((ABS(CHECKSUM(NEWID())) % 60)),                                                  -- 9:00 .. 9:59
        CAST(d.full_date AS DATETIME2(0))),
    N'DEV-' + RIGHT('00' + CAST((u.user_id % 10) + 1 AS VARCHAR(2)), 2),
    N'IN',
    HASHBYTES('SHA2_256', CONCAT(u.user_id, '|', d.full_date, '|IN')),
    N'SEED-2026-04'
FROM   core.dim_user u
CROSS JOIN d
WHERE  u.is_active = 1;
GO

;WITH d AS (
    SELECT full_date
    FROM   core.dim_date
    WHERE  full_date >= '2026-04-01' AND full_date < '2026-05-01'
      AND  is_business_day = 1
)
INSERT INTO core.fact_punch (user_id, punch_at, device_id, direction, row_hash, batch_id)
SELECT
    u.user_id,
    DATEADD(MINUTE,
        1020 + ((ABS(CHECKSUM(NEWID())) % 90)),                                                 -- 17:00..18:29
        CAST(d.full_date AS DATETIME2(0))),
    N'DEV-' + RIGHT('00' + CAST((u.user_id % 10) + 1 AS VARCHAR(2)), 2),
    N'OUT',
    HASHBYTES('SHA2_256', CONCAT(u.user_id, '|', d.full_date, '|OUT')),
    N'SEED-2026-04'
FROM   core.dim_user u
CROSS JOIN d
WHERE  u.is_active = 1
  AND  ABS(CHECKSUM(NEWID())) % 10 > 0;                                                         -- ~10% miss their OUT punch
GO

/* ---------- fact_invoice + fact_payment ----------------------------------- */
;WITH students AS (
    SELECT user_id FROM core.dim_user WHERE role = N'student'
)
INSERT INTO core.fact_invoice (user_id, invoice_no, invoice_date, due_date, amount, balance, status)
SELECT
    s.user_id,
    N'INV-2026-' + RIGHT('00000' + CAST(ROW_NUMBER() OVER (ORDER BY s.user_id) AS VARCHAR(5)), 5),
    '2026-04-01',
    '2026-04-30',
    CAST(25000 + (ABS(CHECKSUM(NEWID())) % 30000) AS DECIMAL(18,2)),
    0,
    N'open'
FROM students s;
GO

-- ~75% of invoices fully paid, ~10% partial, ~15% open and overdue
UPDATE core.fact_invoice
SET    balance = amount,
       status  = N'open'
WHERE  invoice_id % 7 = 0;

UPDATE core.fact_invoice
SET    balance = amount / 2,
       status  = N'partial'
WHERE  invoice_id % 11 = 0;

UPDATE core.fact_invoice
SET    balance = 0,
       status  = N'paid'
WHERE  balance = 0;
GO

INSERT INTO core.fact_payment (invoice_id, paid_at, amount, method, reference_no)
SELECT
    invoice_id,
    DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 25, '2026-04-05'),
    amount - balance,
    CASE ABS(CHECKSUM(NEWID())) % 4
        WHEN 0 THEN N'upi'
        WHEN 1 THEN N'netbank'
        WHEN 2 THEN N'card'
        ELSE        N'cash'
    END,
    N'REF-' + CAST(invoice_id AS NVARCHAR(20))
FROM   core.fact_invoice
WHERE  status IN (N'paid', N'partial');
GO

PRINT N'seed-small complete.  Roughly: 200 users, 6000 punches, 180 invoices.';
PRINT N'Now you can:';
PRINT N'  -- close attendance for one day';
PRINT N'  EXEC mart.sp_close_attendance_day @for_date = ''2026-04-15'';';
PRINT N'';
PRINT N'  -- KPI';
PRINT N'  EXEC mart.sp_kpi_absenteeism @from_date = ''2026-04-01'', @to_date = ''2026-04-30'';';
PRINT N'  EXEC mart.sp_kpi_collection_rate @from_date = ''2026-04-01'', @to_date = ''2026-04-30'';';
GO
