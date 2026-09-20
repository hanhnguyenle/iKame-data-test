
USE [data_test];
GO

------------------------------------------------------------
-- 1. Schemas
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'raw')
    EXEC('CREATE SCHEMA raw');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dwh')
    EXEC('CREATE SCHEMA dwh');
GO


-- first_open: 1 row per user (install/acquisition dimension source)
IF OBJECT_ID('raw.first_open', 'U') IS NOT NULL DROP TABLE raw.first_open;
CREATE TABLE raw.first_open (
    event_date                  NVARCHAR(50),
    event_timestamp             NVARCHAR(50),
    user_id                     NVARCHAR(100),
    app_version                 NVARCHAR(50),
    country                     NVARCHAR(100),
    tier                        NVARCHAR(50),
    city                        NVARCHAR(200),
    language                    NVARCHAR(50),
    operating_system_version    NVARCHAR(100),
    mobile_brand_name           NVARCHAR(100),
    mobile_marketing_name       NVARCHAR(200),
    traffic_source_source       NVARCHAR(100),
    _load_ts                    DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file                NVARCHAR(200) DEFAULT 'first_open.csv'
);
GO



-- session_start: 1 row per user per day (pre-aggregated)
IF OBJECT_ID('raw.session_start', 'U') IS NOT NULL DROP TABLE raw.session_start;
CREATE TABLE raw.session_start (
    event_date      NVARCHAR(50),
    user_id         NVARCHAR(100),
    app_version     NVARCHAR(50),
    country         NVARCHAR(100),
    tier            NVARCHAR(50),
    city            NVARCHAR(200),
    event_count     NVARCHAR(50),
    _load_ts        DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file    NVARCHAR(200) DEFAULT 'session_start.csv'
);
GO


-- user_engagement: 1 row per user per day (pre-aggregated)
IF OBJECT_ID('raw.user_engagement', 'U') IS NOT NULL DROP TABLE raw.user_engagement;
CREATE TABLE raw.user_engagement (
    event_date          NVARCHAR(50),
    user_id              NVARCHAR(100),
    app_version          NVARCHAR(50),
    country              NVARCHAR(100),
    tier                 NVARCHAR(50),
    city                 NVARCHAR(200),
    engagement_time      NVARCHAR(50),
    _load_ts             DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file         NVARCHAR(200) DEFAULT 'user_engagement.csv'
);
GO

-- main_function: 1 row per feature usage event
IF OBJECT_ID('raw.main_function', 'U') IS NOT NULL DROP TABLE raw.main_function;
CREATE TABLE raw.main_function (
    event_date                      NVARCHAR(50),
    event_timestamp                 NVARCHAR(50),
    event_name                      NVARCHAR(50),
    user_id                         NVARCHAR(100),
    app_version                     NVARCHAR(50),
    country                         NVARCHAR(100),
    params_total_number_session     NVARCHAR(50),
    action_type                     NVARCHAR(50),
    function_name                   NVARCHAR(100),
    _load_ts                        DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file                    NVARCHAR(200) DEFAULT 'main_function.csv'
);
GO

-- reminder: 1 row per reminder/dialog/notify event
IF OBJECT_ID('raw.reminder', 'U') IS NOT NULL DROP TABLE raw.reminder;
CREATE TABLE raw.reminder (
    event_date                      NVARCHAR(50),
    event_timestamp                 NVARCHAR(50),
    event_name                      NVARCHAR(50),
    user_id                         NVARCHAR(100),
    app_version                     NVARCHAR(50),
    country                         NVARCHAR(100),
    params_total_number_session     NVARCHAR(50),
    params_remind_type              NVARCHAR(50),
    params_remind_position          NVARCHAR(50),
    params_action_name              NVARCHAR(50),
    _load_ts                        DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file                    NVARCHAR(200) DEFAULT 'reminder.csv'
);
GO

-- ad_impression: 1 row per ad impression event
IF OBJECT_ID('raw.ad_impression', 'U') IS NOT NULL DROP TABLE raw.ad_impression;
CREATE TABLE raw.ad_impression (
    event_date          NVARCHAR(50),
    event_timestamp      NVARCHAR(50),
    event_name           NVARCHAR(50),
    user_id              NVARCHAR(100),
    app_version          NVARCHAR(50),
    country               NVARCHAR(100),
    tier                  NVARCHAR(50),
    params_ad_format      NVARCHAR(50),
    _load_ts              DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file          NVARCHAR(200) DEFAULT 'ad_impression.csv'
);
GO

-- app_remove: 1 row per user (uninstall event)
IF OBJECT_ID('raw.app_remove', 'U') IS NOT NULL DROP TABLE raw.app_remove;
CREATE TABLE raw.app_remove (
    event_date                      NVARCHAR(50),
    user_id                         NVARCHAR(100),
    app_version                     NVARCHAR(50),
    country                         NVARCHAR(100),
    tier                            NVARCHAR(50),
    city                             NVARCHAR(200),
    params_total_number_session     NVARCHAR(50),
    _load_ts                        DATETIME2 DEFAULT SYSUTCDATETIME(),
    _source_file                     NVARCHAR(200) DEFAULT 'app_remove.csv'
);
GO

PRINT 'Schemas [raw],[dwh] and 7 raw tables created.';
