/* ============================================================
   05_build_dwh.sql
   Purpose : Build the dwh layer — DIM_DATE, DIM_USER, and FACT_*
             tables — as physical TABLEs (materialized via SELECT INTO),
             sourced from raw.* (raw.first_open_clean /
             raw.ad_impression_clean for the two deduped tables,
             raw.* directly for the rest — see docs/data_quality_log.md).

   Casting strategy: TRY_CAST is used everywhere a raw text column
   is converted to a typed column. Rows where a cast fails become
   NULL in that column (not dropped) — counts of failed casts were
   already verified as ~0 in 03_data_quality_check.sql section 8.

   Run after: 04_dedupe_raw.sql
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- DWH.DIM_DATE
-- Calendar table covering the full tracked range with headroom
-- (2023-06-01 .. 2023-07-31 is the actual data window).
------------------------------------------------------------
IF OBJECT_ID('dwh.dim_date', 'U') IS NOT NULL DROP TABLE dwh.dim_date;

;WITH seq AS (
    SELECT TOP (DATEDIFF(DAY, '2023-05-25', '2023-08-07') + 1)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
SELECT
    CAST(DATEADD(DAY, n, '2023-05-25') AS DATE) AS date_key,
    DATEPART(YEAR,  DATEADD(DAY, n, '2023-05-25')) AS year_num,
    DATEPART(MONTH, DATEADD(DAY, n, '2023-05-25')) AS month_num,
    DATENAME(MONTH, DATEADD(DAY, n, '2023-05-25')) AS month_name,
    DATEPART(WEEK,  DATEADD(DAY, n, '2023-05-25')) AS week_num,
    DATEPART(WEEKDAY, DATEADD(DAY, n, '2023-05-25')) AS weekday_num,
    DATENAME(WEEKDAY, DATEADD(DAY, n, '2023-05-25')) AS weekday_name,
    CASE WHEN DATEPART(WEEKDAY, DATEADD(DAY, n, '2023-05-25')) IN (1,7) THEN 1 ELSE 0 END AS is_weekend
INTO dwh.dim_date
FROM seq;
GO

ALTER TABLE dwh.dim_date ALTER COLUMN date_key DATE NOT NULL;
GO

ALTER TABLE dwh.dim_date ADD CONSTRAINT PK_dim_date PRIMARY KEY (date_key);
GO

------------------------------------------------------------
-- DWH.DIM_USER
-- Grain: 1 row per user_id. Source: raw.first_open_clean
-- (deduped). Type-0 dimension — install-time attributes only,
-- data has no evidence of user attributes changing over time.
------------------------------------------------------------
IF OBJECT_ID('dwh.dim_user', 'U') IS NOT NULL DROP TABLE dwh.dim_user;

SELECT
    user_id,
    TRY_CAST(event_date AS DATE)              AS install_date,
    TRY_CAST(event_timestamp AS BIGINT)       AS install_timestamp_us,
    app_version                               AS install_app_version,
    NULLIF(LTRIM(RTRIM(country)), '')         AS country,
    NULLIF(LTRIM(RTRIM(tier)), '')            AS tier,
    NULLIF(LTRIM(RTRIM(city)), '')            AS city,
    NULLIF(LTRIM(RTRIM(language)), '')        AS language,
    operating_system_version,
    mobile_brand_name,
    mobile_marketing_name,
    CASE
        WHEN NULLIF(LTRIM(RTRIM(traffic_source_source)), '') IS NULL THEN 'unknown'
        ELSE LOWER(LTRIM(RTRIM(traffic_source_source)))
    END AS traffic_source_source
INTO dwh.dim_user
FROM raw.first_open_clean;

ALTER TABLE dwh.dim_user ADD CONSTRAINT PK_dim_user PRIMARY KEY (user_id);
GO

------------------------------------------------------------
-- DWH.FACT_APP_REMOVE
-- Grain: 1 row per user_id (uninstall event). Kept as its own
-- fact (not folded into dim_user) since it is an event with a
-- date and a measure (session count at time of removal).
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_app_remove', 'U') IS NOT NULL DROP TABLE dwh.fact_app_remove;

SELECT
    r.user_id,
    TRY_CAST(r.event_date AS DATE)                          AS remove_date,
    TRY_CAST(r.params_total_number_session AS INT)          AS total_number_session_at_remove,
    DATEDIFF(DAY, u.install_date, TRY_CAST(r.event_date AS DATE)) AS days_since_install
INTO dwh.fact_app_remove
FROM raw.app_remove r
LEFT JOIN dwh.dim_user u ON u.user_id = r.user_id;
GO

------------------------------------------------------------
-- DWH.FACT_SESSION_DAILY
-- Grain: 1 row per user_id per event_date (already pre-aggregated
-- in source). event_count = number of sessions that day.
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_session_daily', 'U') IS NOT NULL DROP TABLE dwh.fact_session_daily;

SELECT
    s.user_id,
    TRY_CAST(s.event_date AS DATE)                   AS event_date,
    TRY_CAST(s.event_count AS INT)                    AS session_count,
    DATEDIFF(DAY, u.install_date, TRY_CAST(s.event_date AS DATE)) AS days_since_install
INTO dwh.fact_session_daily
FROM raw.session_start s
LEFT JOIN dwh.dim_user u ON u.user_id = s.user_id;
GO

------------------------------------------------------------
-- DWH.FACT_ENGAGEMENT_DAILY
-- Grain: 1 row per user_id per event_date.
-- engagement_time source unit: seconds with decimals (per sample
-- values like 17.529 / 27.281) — kept as DECIMAL, not rounded.
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_engagement_daily', 'U') IS NOT NULL DROP TABLE dwh.fact_engagement_daily;

SELECT
    e.user_id,
    TRY_CAST(e.event_date AS DATE)                          AS event_date,
    TRY_CAST(e.engagement_time AS DECIMAL(18,3))            AS engagement_time_sec,
    DATEDIFF(DAY, u.install_date, TRY_CAST(e.event_date AS DATE)) AS days_since_install
INTO dwh.fact_engagement_daily
FROM raw.user_engagement e
LEFT JOIN dwh.dim_user u ON u.user_id = e.user_id;
GO

------------------------------------------------------------
-- DWH.FACT_MAIN_FUNCTION
-- Grain: 1 row per feature-usage event.
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_main_function', 'U') IS NOT NULL DROP TABLE dwh.fact_main_function;

SELECT
    m.user_id,
    TRY_CAST(m.event_date AS DATE)                   AS event_date,
    TRY_CAST(m.event_timestamp AS BIGINT)            AS event_timestamp_us,
    m.function_name,
    m.action_type,
    TRY_CAST(m.params_total_number_session AS INT)  AS total_number_session,
    DATEDIFF(DAY, u.install_date, TRY_CAST(m.event_date AS DATE)) AS days_since_install
INTO dwh.fact_main_function
FROM raw.main_function m
LEFT JOIN dwh.dim_user u ON u.user_id = m.user_id;
GO

------------------------------------------------------------
-- DWH.FACT_REMINDER
-- Grain: 1 row per reminder/dialog/notify event
-- (show / click / close funnel, by remind_type + position).
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_reminder', 'U') IS NOT NULL DROP TABLE dwh.fact_reminder;

SELECT
    r.user_id,
    TRY_CAST(r.event_date AS DATE)                   AS event_date,
    TRY_CAST(r.event_timestamp AS BIGINT)            AS event_timestamp_us,
    r.params_remind_type                              AS remind_type,
    r.params_remind_position                          AS remind_position,
    r.params_action_name                              AS action_name,
    TRY_CAST(r.params_total_number_session AS INT)   AS total_number_session,
    DATEDIFF(DAY, u.install_date, TRY_CAST(r.event_date AS DATE)) AS days_since_install
INTO dwh.fact_reminder
FROM raw.reminder r
LEFT JOIN dwh.dim_user u ON u.user_id = r.user_id;
GO

------------------------------------------------------------
-- DWH.FACT_AD_IMPRESSION
-- Grain: 1 row per ad impression event. Source: raw.ad_impression_clean
-- (deduped — see docs/data_quality_log.md).
------------------------------------------------------------
IF OBJECT_ID('dwh.fact_ad_impression', 'U') IS NOT NULL DROP TABLE dwh.fact_ad_impression;

SELECT
    a.user_id,
    TRY_CAST(a.event_date AS DATE)                   AS event_date,
    TRY_CAST(a.event_timestamp AS BIGINT)            AS event_timestamp_us,
    a.tier,
    a.params_ad_format                                AS ad_format,
    DATEDIFF(DAY, u.install_date, TRY_CAST(a.event_date AS DATE)) AS days_since_install
INTO dwh.fact_ad_impression
FROM raw.ad_impression_clean a
LEFT JOIN dwh.dim_user u ON u.user_id = a.user_id;
GO

------------------------------------------------------------
-- Indexes to support dashboard-style filtering/joins
------------------------------------------------------------
CREATE INDEX IX_fact_app_remove_user      ON dwh.fact_app_remove (user_id);
CREATE INDEX IX_fact_session_user_date    ON dwh.fact_session_daily (user_id, event_date);
CREATE INDEX IX_fact_engagement_user_date ON dwh.fact_engagement_daily (user_id, event_date);
CREATE INDEX IX_fact_main_function_user   ON dwh.fact_main_function (user_id, event_date);
CREATE INDEX IX_fact_reminder_user        ON dwh.fact_reminder (user_id, event_date);
CREATE INDEX IX_fact_ad_impression_user   ON dwh.fact_ad_impression (user_id, event_date);
CREATE INDEX IX_dim_user_traffic_tier     ON dwh.dim_user (traffic_source_source, tier);
GO

------------------------------------------------------------
-- Verify: row counts across dwh layer
------------------------------------------------------------
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dwh.dim_date
UNION ALL SELECT 'dim_user', COUNT(*) FROM dwh.dim_user
UNION ALL SELECT 'fact_app_remove', COUNT(*) FROM dwh.fact_app_remove
UNION ALL SELECT 'fact_session_daily', COUNT(*) FROM dwh.fact_session_daily
UNION ALL SELECT 'fact_engagement_daily', COUNT(*) FROM dwh.fact_engagement_daily
UNION ALL SELECT 'fact_main_function', COUNT(*) FROM dwh.fact_main_function
UNION ALL SELECT 'fact_reminder', COUNT(*) FROM dwh.fact_reminder
UNION ALL SELECT 'fact_ad_impression', COUNT(*) FROM dwh.fact_ad_impression;
GO

------------------------------------------------------------
-- Verify: any fact rows that failed to join to dim_user
-- (orphans — should match the counts already seen in
-- 03_data_quality_check.sql section 4)
------------------------------------------------------------
SELECT 'fact_app_remove'        AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_app_remove        WHERE days_since_install IS NULL;
SELECT 'fact_session_daily'     AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_session_daily     WHERE days_since_install IS NULL;
SELECT 'fact_engagement_daily'  AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_engagement_daily  WHERE days_since_install IS NULL;
SELECT 'fact_main_function'     AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_main_function     WHERE days_since_install IS NULL;
SELECT 'fact_reminder'          AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_reminder          WHERE days_since_install IS NULL;
SELECT 'fact_ad_impression'     AS table_name, COUNT(*) AS unmatched_users FROM dwh.fact_ad_impression     WHERE days_since_install IS NULL;
GO
