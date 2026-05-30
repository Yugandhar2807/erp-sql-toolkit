/* =============================================================================
   install-tsqlt.sql
   How to install tSQLt in this demo database.

   tSQLt is an MIT-licensed unit-testing framework for SQL Server.
   We do not redistribute it here — fetch directly from the official site.

   STEPS:
   1. Download the latest tSQLt zip from https://tsqlt.org/downloads/
   2. Extract.  You'll see PrepareServer.sql, tSQLt.class.sql, tSQLt_OutputText.sql
   3. Connect to your ERPToolkitDemo database
   4. Run PrepareServer.sql       (one-time per SQL Server instance)
   5. Run tSQLt.class.sql         (installs tSQLt schema into current DB)
   6. Verify with:
        EXEC tSQLt.Info;
        SELECT * FROM tSQLt.TestClasses;
   7. Then run the test classes shipped here:
        EXEC tSQLt.Run 'imports';
        EXEC tSQLt.Run 'scd2_tests';
        EXEC tSQLt.Run 'dq_tests';
      Or run everything:
        EXEC tSQLt.RunAll;
   ============================================================================= */

USE ERPToolkitDemo;
GO
PRINT N'Read this file, then download tSQLt manually from https://tsqlt.org/downloads/';
GO
