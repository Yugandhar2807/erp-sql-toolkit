/* =============================================================================
   fn_age_in_years.sql
   Age in completed years between two dates (does NOT round up).
   Returns NULL if either input is NULL.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER FUNCTION util.fn_age_in_years
(
    @birth DATE,
    @as_of DATE
)
RETURNS INT
AS
BEGIN
    IF @birth IS NULL OR @as_of IS NULL
        RETURN NULL;

    DECLARE @age INT = DATEDIFF(YEAR, @birth, @as_of);

    -- Roll back one year if @as_of hasn't reached the birthday yet
    IF DATEADD(YEAR, @age, @birth) > @as_of
        SET @age = @age - 1;

    RETURN @age;
END
GO
PRINT N'util.fn_age_in_years created';
GO
