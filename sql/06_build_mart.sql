/* ============================================================
   06_build_mart.sql
   Purpose : Build the mart layer — VIEWs on top of dwh, this is
             the ONLY schema Power BI should import from.

   Design  : star schema, kept normalized (not denormalized).
             Fact views expose user_id as an FK only; Power BI
             Desktop creates the relationships to mart.dim_user /
             mart.dim_date after import. This keeps one shared
             dim_user (no duplicated country/tier/traffic_source
             copied into every fact row), and any slicer built on
             dim_user (country, tier, traffic_source) filters every
             fact table through its relationship automatically.

   Contents:
     mart.dim_user            - 1 row / user (pass-through of dwh.dim_user)
     mart.dim_date            - 1 row / calendar day (pass-through of dwh.dim_date)
     mart.dim_ecpm            - tier x ad_format -> eCPM, hand-entered from
                                 the brief (not derivable from tracking data)
     mart.fact_daily_activity - 1 row / user / day, session_count +
                                 engagement_time_sec unioned (session_start
                                 and user_engagement share the same grain)
     mart.fact_main_function  - pass-through of dwh.fact_main_function
     mart.fact_reminder       - pass-through of dwh.fact_reminder
     mart.fact_ad_impression  - dwh.fact_ad_impression + eCPM joined in,
                                 with a pre-computed est_revenue column
                                 (so no PBI user need re-derive the eCPM
                                 lookup logic in DAX)
     mart.fact_app_remove     - pass-through of dwh.fact_app_remove

   Run after: 05_build_dwh.sql
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- MART.DIM_USER
------------------------------------------------------------
IF OBJECT_ID('mart.dim_user', 'V') IS NOT NULL DROP VIEW mart.dim_user;
GO
CREATE VIEW mart.dim_user AS
SELECT
    user_id,
    install_date,
    install_app_version,
    country,
    tier,
    city,
    language,
    operating_system_version,
    mobile_brand_name,
    mobile_marketing_name,
    traffic_source_source
FROM dwh.dim_user;
GO

------------------------------------------------------------
-- MART.DIM_DATE
------------------------------------------------------------
IF OBJECT_ID('mart.dim_date', 'V') IS NOT NULL DROP VIEW mart.dim_date;
GO
CREATE VIEW mart.dim_date AS
SELECT
    date_key,
    year_num,
    month_num,
    month_name,
    week_num,
    weekday_num,
    weekday_name,
    is_weekend
FROM dwh.dim_date;
GO

------------------------------------------------------------
-- MART.DIM_ECPM
-- Hand-entered from the brief's eCPM table (question 3).
-- Not derivable from any tracking data — this is business input.
-- Currency: USD, value = revenue per 1,000 impressions.
--
-- The brief's table has five tier rows: Tier01-04 plus an unnamed
-- row for impressions whose tier is unknown. A NULL cannot sit in a
-- primary key, so that row is stored under the sentinel 'unknown'
-- and matched via COALESCE in mart.fact_ad_impression below —
-- letting the ~2,300 impressions from users outside the tracking
-- window (no dim_user record, hence no tier) be priced rather than
-- dropped from revenue.
------------------------------------------------------------
IF OBJECT_ID('mart.dim_ecpm', 'U') IS NOT NULL DROP TABLE mart.dim_ecpm;
GO
CREATE TABLE mart.dim_ecpm (
    tier        NVARCHAR(50)    NOT NULL,
    ad_format   NVARCHAR(50)    NOT NULL,
    ecpm_usd    DECIMAL(10,4)   NOT NULL,
    CONSTRAINT PK_dim_ecpm PRIMARY KEY (tier, ad_format)
);
GO

INSERT INTO mart.dim_ecpm (tier, ad_format, ecpm_usd) VALUES
    ('Tier01',  'banner',       1.41),
    ('Tier01',  'interstitial', 9.45),
    ('Tier01',  'open_ad',      7.30),
    ('Tier02',  'banner',       0.55),
    ('Tier02',  'interstitial', 3.78),
    ('Tier02',  'open_ad',      2.55),
    ('Tier03',  'banner',       0.26),
    ('Tier03',  'interstitial', 1.35),
    ('Tier03',  'open_ad',      0.93),
    ('Tier04',  'banner',       0.06),
    ('Tier04',  'interstitial', 0.38),
    ('Tier04',  'open_ad',      0.32),
    ('unknown', 'banner',       0.14),
    ('unknown', 'interstitial', 0.90),
    ('unknown', 'open_ad',      0.59);
GO

------------------------------------------------------------
-- MART.FACT_DAILY_ACTIVITY
-- Grain: 1 row per user_id per event_date.
-- Unions session_start and user_engagement (same source grain)
-- into one row per user/day, so Overview- and Engagement-page
-- visuals (DAU, avg session, avg engagement time) read from a
-- single table instead of two separately-grained facts.
-- FULL OUTER JOIN: a user can have a session_start row without a
-- matching user_engagement row that day, or vice versa.
------------------------------------------------------------
IF OBJECT_ID('mart.fact_daily_activity', 'V') IS NOT NULL DROP VIEW mart.fact_daily_activity;
GO
CREATE VIEW mart.fact_daily_activity AS
SELECT
    COALESCE(s.user_id, e.user_id)             AS user_id,
    COALESCE(s.event_date, e.event_date)       AS event_date,
    s.session_count,
    e.engagement_time_sec,
    COALESCE(s.days_since_install, e.days_since_install) AS days_since_install
FROM dwh.fact_session_daily s
FULL OUTER JOIN dwh.fact_engagement_daily e
    ON e.user_id = s.user_id AND e.event_date = s.event_date;
GO

------------------------------------------------------------
-- MART.FACT_MAIN_FUNCTION
------------------------------------------------------------
IF OBJECT_ID('mart.fact_main_function', 'V') IS NOT NULL DROP VIEW mart.fact_main_function;
GO
CREATE VIEW mart.fact_main_function AS
SELECT
    user_id,
    event_date,
    function_name,
    action_type,
    total_number_session,
    days_since_install
FROM dwh.fact_main_function;
GO

------------------------------------------------------------
-- MART.FACT_REMINDER
------------------------------------------------------------
IF OBJECT_ID('mart.fact_reminder', 'V') IS NOT NULL DROP VIEW mart.fact_reminder;
GO
CREATE VIEW mart.fact_reminder AS
SELECT
    user_id,
    event_date,
    remind_type,
    remind_position,
    action_name,
    total_number_session,
    days_since_install
FROM dwh.fact_reminder;
GO

------------------------------------------------------------
-- MART.FACT_AD_IMPRESSION
-- dwh.fact_ad_impression joined to mart.dim_ecpm on (tier, ad_format)
-- so est_revenue_usd is pre-computed per impression — PBI just
-- SUMs it, no DAX lookup logic needed. est_revenue_usd = eCPM / 1000
-- (eCPM is revenue per 1,000 impressions; each row is 1 impression).
------------------------------------------------------------
IF OBJECT_ID('mart.fact_ad_impression', 'V') IS NOT NULL DROP VIEW mart.fact_ad_impression;
GO
CREATE VIEW mart.fact_ad_impression AS
SELECT
    a.user_id,
    a.event_date,
    a.tier,
    a.ad_format,
    a.days_since_install,
    c.ecpm_usd,
    CAST(c.ecpm_usd / 1000.0 AS DECIMAL(10,6)) AS est_revenue_usd
FROM dwh.fact_ad_impression a
LEFT JOIN mart.dim_ecpm c
    -- COALESCE routes an impression with no tier to the brief's
    -- unnamed price row (stored as 'unknown'), so it is priced
    -- instead of falling out of every revenue figure. The tier
    -- column itself is left as-is (NULL) so reports can still
    -- show these separately.
    ON c.tier = COALESCE(NULLIF(LTRIM(RTRIM(a.tier)), ''), 'unknown')
   AND c.ad_format = a.ad_format;
GO

------------------------------------------------------------
-- MART.FACT_APP_REMOVE
------------------------------------------------------------
IF OBJECT_ID('mart.fact_app_remove', 'V') IS NOT NULL DROP VIEW mart.fact_app_remove;
GO
CREATE VIEW mart.fact_app_remove AS
SELECT
    user_id,
    remove_date,
    total_number_session_at_remove,
    days_since_install
FROM dwh.fact_app_remove;
GO

------------------------------------------------------------
-- Verify: row counts + sanity checks
------------------------------------------------------------
SELECT 'mart.dim_user' AS view_name, COUNT(*) AS row_count FROM mart.dim_user
UNION ALL SELECT 'mart.dim_date', COUNT(*) FROM mart.dim_date
UNION ALL SELECT 'mart.dim_ecpm', COUNT(*) FROM mart.dim_ecpm
UNION ALL SELECT 'mart.fact_daily_activity', COUNT(*) FROM mart.fact_daily_activity
UNION ALL SELECT 'mart.fact_main_function', COUNT(*) FROM mart.fact_main_function
UNION ALL SELECT 'mart.fact_reminder', COUNT(*) FROM mart.fact_reminder
UNION ALL SELECT 'mart.fact_ad_impression', COUNT(*) FROM mart.fact_ad_impression
UNION ALL SELECT 'mart.fact_app_remove', COUNT(*) FROM mart.fact_app_remove;
GO

-- fact_ad_impression rows that failed to match an eCPM — should now be
-- 0 in every case: tier is Tier01-04 or NULL (routed to 'unknown' by
-- the COALESCE in the view), and ad_format is always one of the three
-- the brief prices
SELECT COUNT(*) AS unmatched_ecpm_rows
FROM mart.fact_ad_impression
WHERE ecpm_usd IS NULL;
GO

-- Impressions priced at the 'unknown' tier rate, and what they add to
-- estimated revenue. These are impressions from users who installed
-- before the tracking window opened, so no tier could be recovered.
-- Before the 'unknown' row was added they contributed $0.
SELECT
    COUNT(*)                                   AS untiered_impressions,
    CAST(SUM(est_revenue_usd) AS DECIMAL(12,4)) AS revenue_added_usd
FROM mart.fact_ad_impression
WHERE tier IS NULL;
GO

-- Total estimated revenue, to compare against the figure the dashboard
-- showed before this change ($486.794)
SELECT CAST(SUM(est_revenue_usd) AS DECIMAL(12,4)) AS est_total_revenue_usd
FROM mart.fact_ad_impression;
GO

-- fact_daily_activity: confirm no duplicate (user_id, event_date) —
-- the FULL OUTER JOIN should produce at most 1 row per user/day
SELECT COUNT(*) AS dup_user_day_rows
FROM (
    SELECT user_id, event_date
    FROM mart.fact_daily_activity
    GROUP BY user_id, event_date
    HAVING COUNT(*) > 1
) t;
GO
