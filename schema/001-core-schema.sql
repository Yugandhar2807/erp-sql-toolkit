/* =============================================================================
   001-core-schema.sql
   Core dimensions + facts used by the rest of the toolkit.
   Domain: generic education ERP (students, programs, attendance, payments).
   All synthetic — no employer schema or naming.
   ============================================================================= */

USE ERPToolkitDemo;
GO
SET NOCOUNT ON;
GO

/* ---------- DIM_DATE -------------------------------------------------------- */
IF OBJECT_ID(N'core.dim_date', N'U') IS NOT NULL DROP TABLE core.dim_date;
GO
CREATE TABLE core.dim_date
(
    date_id           INT          NOT NULL PRIMARY KEY,         -- YYYYMMDD
    full_date         DATE         NOT NULL,
    day_of_month      TINYINT      NOT NULL,
    day_of_week       TINYINT      NOT NULL,                     -- 1..7 (Mon..Sun)
    day_name          NVARCHAR(10) NOT NULL,
    week_of_year      TINYINT      NOT NULL,
    month_of_year     TINYINT      NOT NULL,
    month_name        NVARCHAR(10) NOT NULL,
    quarter_of_year   TINYINT      NOT NULL,
    year              SMALLINT     NOT NULL,
    is_weekend        BIT          NOT NULL,
    is_business_day   BIT          NOT NULL                      -- excl. weekends; holidays handled via core.holiday
);
GO

/* ---------- DIM_PROGRAM ----------------------------------------------------- */
IF OBJECT_ID(N'core.dim_program', N'U') IS NOT NULL DROP TABLE core.dim_program;
GO
CREATE TABLE core.dim_program
(
    program_id        INT IDENTITY(1,1) PRIMARY KEY,
    program_code      NVARCHAR(20)  NOT NULL UNIQUE,
    program_name      NVARCHAR(120) NOT NULL,
    program_type      NVARCHAR(40)  NOT NULL,                   -- UG | PG | Diploma
    duration_years    TINYINT       NOT NULL,
    is_active         BIT           NOT NULL DEFAULT 1,
    created_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- DIM_USER (SCD Type 1 reference) -------------------------------- */
IF OBJECT_ID(N'core.dim_user', N'U') IS NOT NULL DROP TABLE core.dim_user;
GO
CREATE TABLE core.dim_user
(
    user_id           INT IDENTITY(1,1) PRIMARY KEY,
    external_ref      NVARCHAR(64)  NOT NULL UNIQUE,            -- card / biometric ID
    full_name         NVARCHAR(200) NOT NULL,
    role              NVARCHAR(20)  NOT NULL,                   -- student | faculty | staff
    email             NVARCHAR(200) NULL,
    phone             NVARCHAR(20)  NULL,
    program_id        INT           NULL REFERENCES core.dim_program(program_id),
    joined_on         DATE          NOT NULL,
    is_active         BIT           NOT NULL DEFAULT 1,
    created_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX ix_dim_user_role_active ON core.dim_user(role, is_active) INCLUDE(program_id);
GO

/* ---------- HOLIDAY --------------------------------------------------------- */
IF OBJECT_ID(N'core.holiday', N'U') IS NOT NULL DROP TABLE core.holiday;
GO
CREATE TABLE core.holiday
(
    holiday_date      DATE          NOT NULL PRIMARY KEY,
    holiday_name      NVARCHAR(120) NOT NULL,
    is_public         BIT           NOT NULL DEFAULT 1
);
GO

/* ---------- FACT_PUNCH (raw biometric events) ------------------------------ */
IF OBJECT_ID(N'core.fact_punch', N'U') IS NOT NULL DROP TABLE core.fact_punch;
GO
CREATE TABLE core.fact_punch
(
    punch_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id           INT          NOT NULL REFERENCES core.dim_user(user_id),
    punch_at          DATETIME2(0) NOT NULL,
    device_id         NVARCHAR(64) NOT NULL,
    direction         CHAR(3)      NOT NULL CHECK (direction IN ('IN', 'OUT')),
    row_hash          BINARY(32)   NOT NULL,                    -- SHA2_256(user|time|device|dir)
    batch_id          NVARCHAR(64) NOT NULL,
    ingested_at       DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE UNIQUE INDEX uq_fact_punch_event ON core.fact_punch(user_id, punch_at, device_id, direction);
CREATE INDEX ix_fact_punch_batch ON core.fact_punch(batch_id);
GO

/* ---------- FACT_DAILY_ATTENDANCE (rolled up by sp_close_attendance_day) --- */
IF OBJECT_ID(N'mart.fact_daily_attendance', N'U') IS NOT NULL DROP TABLE mart.fact_daily_attendance;
GO
CREATE TABLE mart.fact_daily_attendance
(
    user_id           INT          NOT NULL REFERENCES core.dim_user(user_id),
    attendance_date   DATE         NOT NULL,
    first_in          DATETIME2(0) NULL,
    last_out          DATETIME2(0) NULL,
    duration_minutes  INT          NULL,
    status            NVARCHAR(20) NOT NULL,                    -- present | absent | half-day | late
    closed_at         DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_fact_daily_attendance PRIMARY KEY (user_id, attendance_date)
);
GO
CREATE INDEX ix_fact_daily_attendance_status ON mart.fact_daily_attendance(status, attendance_date);
GO

/* ---------- FACT_INVOICE + FACT_PAYMENT (finance) -------------------------- */
IF OBJECT_ID(N'core.fact_invoice', N'U') IS NOT NULL DROP TABLE core.fact_invoice;
GO
CREATE TABLE core.fact_invoice
(
    invoice_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id           INT           NOT NULL REFERENCES core.dim_user(user_id),
    invoice_no        NVARCHAR(40)  NOT NULL UNIQUE,
    invoice_date      DATE          NOT NULL,
    due_date          DATE          NOT NULL,
    amount            DECIMAL(18,2) NOT NULL CHECK (amount >= 0),
    balance           DECIMAL(18,2) NOT NULL,
    status            NVARCHAR(20)  NOT NULL,                  -- open | paid | partial | overdue | cancelled
    created_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX ix_fact_invoice_user_date ON core.fact_invoice(user_id, invoice_date);
CREATE INDEX ix_fact_invoice_status_due ON core.fact_invoice(status, due_date) WHERE balance > 0;
GO

IF OBJECT_ID(N'core.fact_payment', N'U') IS NOT NULL DROP TABLE core.fact_payment;
GO
CREATE TABLE core.fact_payment
(
    payment_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    invoice_id        BIGINT        NOT NULL REFERENCES core.fact_invoice(invoice_id),
    paid_at           DATETIME2(0)  NOT NULL,
    amount            DECIMAL(18,2) NOT NULL CHECK (amount > 0),
    method            NVARCHAR(20)  NOT NULL,                  -- cash | card | upi | netbank | cheque
    reference_no      NVARCHAR(80)  NULL,
    created_at        DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX ix_fact_payment_invoice ON core.fact_payment(invoice_id, paid_at);
GO

/* ---------- STAGING tables (used by import procs) -------------------------- */
IF OBJECT_ID(N'stg.punch_raw', N'U') IS NOT NULL DROP TABLE stg.punch_raw;
GO
CREATE TABLE stg.punch_raw
(
    stg_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id          NVARCHAR(64)  NOT NULL,
    user_external_ref NVARCHAR(64)  NOT NULL,
    punch_at          DATETIME2(0)  NOT NULL,
    device_id         NVARCHAR(64)  NOT NULL,
    direction         NVARCHAR(10)  NOT NULL,
    loaded_at         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE INDEX ix_stg_punch_batch ON stg.punch_raw(batch_id);
GO

PRINT N'Core schema created: dim_date, dim_program, dim_user, holiday, fact_punch, fact_daily_attendance, fact_invoice, fact_payment, stg.punch_raw';
GO
