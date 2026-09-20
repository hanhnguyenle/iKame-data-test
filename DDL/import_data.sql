/* ============================================================
   02_import_raw_data.sql
   Purpose : Load the 7 source CSVs into raw.* tables.
   Method  : BULK INSERT (fastest, works when SQL Server engine
             account can read the file path directly).

   >>> BEFORE RUNNING: replace @csv_folder below with the actual
       folder path visible to your SQL Server instance, e.g.:
       'D:\DA Test - 2026\'  (if SQL Server runs on the same machine
        and the service account has read access to that folder)

   If BULK INSERT fails with access-denied (common when SQL Server
   runs under a service account without rights to your user folder):
     Option A: copy the CSVs to a folder granted to the SQL Server
               service account (e.g. C:\SQLImport\) and update the path.
     Option B: use SSMS > right-click database > Tasks > Import Flat File
               (wizard), pointing each CSV at its matching raw.<table>.
             Both achieve the same raw.* result; the rest of this
             pipeline does not care which method you used.
   ============================================================ */

USE data_test;
GO

DECLARE @csv_folder NVARCHAR(500) = 'D:\DA Test - 2026\';

------------------------------------------------------------
-- Truncate before reload (idempotent re-runs)
------------------------------------------------------------
TRUNCATE TABLE raw.first_open;
TRUNCATE TABLE raw.session_start;
TRUNCATE TABLE raw.user_engagement;
TRUNCATE TABLE raw.main_function;
TRUNCATE TABLE raw.reminder;
TRUNCATE TABLE raw.ad_impression;
TRUNCATE TABLE raw.app_remove;
GO

------------------------------------------------------------
-- first_open.csv
------------------------------------------------------------
BULK INSERT raw.first_open
FROM 'D:\DA Test - 2026\first_open.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    FIELDQUOTE = '"',
    CODEPAGE = '65001',      -- UTF-8
    TABLOCK,
    KEEPNULLS
);
GO

------------------------------------------------------------
-- session_start.csv
------------------------------------------------------------
BULK INSERT raw.session_start
FROM 'D:\DA Test - 2026\session_start.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS
);
GO

------------------------------------------------------------
-- user_engagement.csv
------------------------------------------------------------
BULK INSERT raw.user_engagement
FROM 'D:\DA Test - 2026\user_engagement.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS
);
GO

------------------------------------------------------------
-- main_function.csv
------------------------------------------------------------
BULK INSERT raw.main_function
FROM 'D:\DA Test - 2026\main_function.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS
);
GO

------------------------------------------------------------
-- reminder.csv
------------------------------------------------------------
BULK INSERT raw.reminder
FROM 'D:\DA Test - 2026\reminder.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS
);
GO

------------------------------------------------------------
-- ad_impression.csv  (~1M rows — largest file)
------------------------------------------------------------
BULK INSERT raw.ad_impression
FROM 'D:\DA Test - 2026\ad_impression.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS, BATCHSIZE = 100000
);
GO

------------------------------------------------------------
-- app_remove.csv
------------------------------------------------------------
BULK INSERT raw.app_remove
FROM 'D:\DA Test - 2026\app_remove.csv'
WITH (
    FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a', FIELDQUOTE = '"', CODEPAGE = '65001',
    TABLOCK, KEEPNULLS
);
GO

------------------------------------------------------------
-- Row count sanity check vs. expected source row counts
-- (expected counts = wc -l source.csv minus header)
------------------------------------------------------------
SELECT 'first_open'      AS table_name, COUNT(*) AS loaded_rows, 136324 AS expected_rows FROM raw.first_open
UNION ALL SELECT 'session_start',    COUNT(*), 321169  FROM raw.session_start
UNION ALL SELECT 'user_engagement',  COUNT(*), 322708  FROM raw.user_engagement
UNION ALL SELECT 'main_function',    COUNT(*), 707743  FROM raw.main_function
UNION ALL SELECT 'reminder',         COUNT(*), 459974  FROM raw.reminder
UNION ALL SELECT 'ad_impression',    COUNT(*), 1016168 FROM raw.ad_impression
UNION ALL SELECT 'app_remove',       COUNT(*), 70625   FROM raw.app_remove;
GO
