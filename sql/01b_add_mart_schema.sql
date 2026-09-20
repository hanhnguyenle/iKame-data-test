/* ============================================================
   01b_add_mart_schema.sql
   Purpose : Add the [mart] schema to an already-existing database
             (run this instead of re-running 01 from scratch if
             raw/dwh already exist).
   ============================================================ */

USE data_test;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mart')
    EXEC('CREATE SCHEMA mart');
GO

PRINT 'Schema [mart] ready.';
