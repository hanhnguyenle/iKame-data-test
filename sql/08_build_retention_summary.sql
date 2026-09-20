/* ============================================================
   08_build_retention_summary.sql
   Purpose : Pre-compute D1 / D7 / D30 Retention as flat, ready-to-use
             numbers — so Power BI KPI cards just SUM two columns
             instead of writing DAX with USERELATIONSHIP / ALL() /
             per-N cohort-maturity logic (see investigation: the
             DAX version mixed an unfiltered "Cohort Size" with a
             maturity-filtered "Active Users", producing a different
             number than mart.fact_retention_curve's D1 point).

   Key idea (the "mature cohort" fix): a user installed on
   2023-07-30 cannot have a D7 data point yet (no data exists past
   2023-07-31), so they must NOT be counted in the D7 denominator.
   Each of D1/D7/D30 below therefore uses its OWN cohort — only
   users whose install_date is at least N days before the last
   tracked date (MAX(event_date) across all fact tables) are
   included, for both the denominator (cohort_size) and numerator
   (active_users).

   Grain   : 1 row total (not per day/cohort) — 3 columns, one pair
             of (cohort_size, active_users) per N in {1,7,30}, plus
             the ratio pre-divided. Import this whole row into Power
             BI and bind D1/D7/D30 Retention KPI cards directly to
             retention_d1_pct / retention_d7_pct / retention_d30_pct
             — no measure, no DAX.

   Run after: 06_build_mart.sql (uses mart.dim_user, mart.fact_daily_activity)
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- MART.FACT_RETENTION_SUMMARY
------------------------------------------------------------
IF OBJECT_ID('mart.fact_retention_summary', 'V') IS NOT NULL DROP VIEW mart.fact_retention_summary;
GO
CREATE VIEW mart.fact_retention_summary AS
WITH last_tracked_date AS (
    -- the last calendar date with any activity data at all — the
    -- "today" that decides whether a cohort has had enough time to
    -- be observed at D-N. Hardcode instead if you want this frozen
    -- to the known data window (2023-07-31) rather than recomputed
    -- on every refresh.
    SELECT MAX(event_date) AS max_date FROM mart.fact_daily_activity
),
cohort_d1 AS (
    SELECT u.user_id
    FROM mart.dim_user u, last_tracked_date d
    WHERE u.install_date <= DATEADD(DAY, -1, d.max_date)
),
cohort_d7 AS (
    SELECT u.user_id
    FROM mart.dim_user u, last_tracked_date d
    WHERE u.install_date <= DATEADD(DAY, -7, d.max_date)
),
cohort_d30 AS (
    SELECT u.user_id
    FROM mart.dim_user u, last_tracked_date d
    WHERE u.install_date <= DATEADD(DAY, -30, d.max_date)
),
active_d1 AS (
    SELECT DISTINCT a.user_id
    FROM mart.fact_daily_activity a
    JOIN cohort_d1 c ON c.user_id = a.user_id
    WHERE a.days_since_install = 1
),
active_d7 AS (
    SELECT DISTINCT a.user_id
    FROM mart.fact_daily_activity a
    JOIN cohort_d7 c ON c.user_id = a.user_id
    WHERE a.days_since_install = 7
),
active_d30 AS (
    SELECT DISTINCT a.user_id
    FROM mart.fact_daily_activity a
    JOIN cohort_d30 c ON c.user_id = a.user_id
    WHERE a.days_since_install = 30
)
SELECT
    (SELECT COUNT(*) FROM cohort_d1)   AS cohort_size_d1,
    (SELECT COUNT(*) FROM active_d1)   AS active_users_d1,
    CAST((SELECT COUNT(*) FROM active_d1) AS DECIMAL(10,4))
        / NULLIF((SELECT COUNT(*) FROM cohort_d1), 0)   AS retention_d1_pct,

    (SELECT COUNT(*) FROM cohort_d7)   AS cohort_size_d7,
    (SELECT COUNT(*) FROM active_d7)   AS active_users_d7,
    CAST((SELECT COUNT(*) FROM active_d7) AS DECIMAL(10,4))
        / NULLIF((SELECT COUNT(*) FROM cohort_d7), 0)   AS retention_d7_pct,

    (SELECT COUNT(*) FROM cohort_d30)  AS cohort_size_d30,
    (SELECT COUNT(*) FROM active_d30)  AS active_users_d30,
    CAST((SELECT COUNT(*) FROM active_d30) AS DECIMAL(10,4))
        / NULLIF((SELECT COUNT(*) FROM cohort_d30), 0)  AS retention_d30_pct;
GO

------------------------------------------------------------
-- Verify
------------------------------------------------------------
SELECT * FROM mart.fact_retention_summary;
GO

-- Sanity check: cohort_size should shrink as N grows (fewer users
-- installed early enough to be "mature" at D30 than at D1), and
-- each retention_pct should be between 0 and 1
SELECT
    cohort_size_d1, cohort_size_d7, cohort_size_d30,
    retention_d1_pct, retention_d7_pct, retention_d30_pct
FROM mart.fact_retention_summary
WHERE cohort_size_d1 < cohort_size_d7   -- should return 0 rows (d1 cohort must be >= d7 cohort)
   OR cohort_size_d7 < cohort_size_d30  -- should return 0 rows
   OR retention_d1_pct NOT BETWEEN 0 AND 1
   OR retention_d7_pct NOT BETWEEN 0 AND 1
   OR retention_d30_pct NOT BETWEEN 0 AND 1;
GO
