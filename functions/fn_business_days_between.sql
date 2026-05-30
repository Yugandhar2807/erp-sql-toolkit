/* =============================================================================
   fn_business_days_between.sql
   Returns count of business days between two dates (inclusive), excluding
   weekends and rows in core.holiday.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER FUNCTION util.fn_business_days_between
(
    @from_date DATE,
    @to_date   DATE
)
RETURNS INT
AS
BEGIN
    DECLARE @result INT;

    SELECT @result = COUNT(*)
    FROM   core.dim_date d
    LEFT   JOIN core.holiday h ON h.holiday_date = d.full_date
    WHERE  d.full_date BETWEEN @from_date AND @to_date
      AND  d.is_business_day = 1
      AND  h.holiday_date IS NULL;

    RETURN ISNULL(@result, 0);
END
GO
PRINT N'util.fn_business_days_between created';
GO
