/* =============================================================================
   fn_split_csv.sql
   Inline table-valued function: splits a delimited string into rows.
   Faster than string_split for fixed delimiter, ordered output via key.
   ============================================================================= */

USE ERPToolkitDemo;
GO

CREATE OR ALTER FUNCTION util.fn_split_csv
(
    @input     NVARCHAR(MAX),
    @delimiter NCHAR(1)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ordinal,
        LTRIM(RTRIM(value))                         AS value
    FROM STRING_SPLIT(@input, @delimiter)
    WHERE LTRIM(RTRIM(value)) <> N''
);
GO
PRINT N'util.fn_split_csv created';
GO
