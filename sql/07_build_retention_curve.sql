/* ============================================================
   07_build_retention_curve.sql
   Purpose : Pre-aggregate cohort retention curves so Power BI's
             "Retention Curve theo tuần cài đặt" line chart (X =
             days_since_install, Legend = install cohort week,
             Y = % active) reads a small flat table instead of
             computing a double cohort filter (TREATAS) in DAX on
             every slicer interaction.

   Grain   : 1 row per (cohort_year, cohort_week, days_since_install).
             cohort_week groups users by the calendar week of
             mart.dim_user.install_date (Mon-Sun, matches the
             week_num convention already in mart.dim_date).

   Contents:
     mart.fact_retention_curve - cohort_size, active_users,
                                 retention_pct per cohort week x day-N

   Run after: 06_build_mart.sql
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- MART.DIM_DAYS_SINCE_INSTALL
-- Static 0..30 day-N axis. A plain table (not a recursive CTE)
-- because SQL Server does not allow OPTION (MAXRECURSION ...) —
-- required by recursive CTEs — inside a CREATE VIEW body.
-- Extend the range below (and re-run) if you need D60/D90 later.
------------------------------------------------------------
IF OBJECT_ID('mart.dim_days_since_install', 'U') IS NOT NULL DROP TABLE mart.dim_days_since_install;
GO
CREATE TABLE mart.dim_days_since_install (
    days_since_install INT NOT NULL PRIMARY KEY
);
GO
INSERT INTO mart.dim_days_since_install (days_since_install)
SELECT TOP (31) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
FROM sys.all_objects;
GO

------------------------------------------------------------
-- MART.FACT_RETENTION_CURVE
------------------------------------------------------------
IF OBJECT_ID('mart.fact_retention_curve', 'V') IS NOT NULL DROP VIEW mart.fact_retention_curve;
GO
CREATE VIEW mart.fact_retention_curve AS
WITH last_tracked_date AS (
    -- last calendar date with any activity data — decides whether a
    -- cohort has had the chance to be observed at day N
    SELECT MAX(event_date) AS max_date FROM mart.fact_daily_activity
),
cohort AS (
    -- 1 row per user, tagged with the Mon-Sun week of their install_date
    SELECT
        u.user_id,
        u.install_date,
        d.year_num                                          AS cohort_year,
        d.week_num                                           AS cohort_week,
        MIN(d2.date_key) OVER (PARTITION BY d.year_num, d.week_num) AS cohort_week_start,
        MAX(d2.date_key) OVER (PARTITION BY d.year_num, d.week_num) AS cohort_week_end
    FROM mart.dim_user u
    JOIN mart.dim_date d
        ON d.date_key = u.install_date
    JOIN mart.dim_date d2
        ON d2.year_num = d.year_num AND d2.week_num = d.week_num
),
cohort_week AS (
    -- collapse to 1 row per (cohort_year, cohort_week) with its label + size.
    -- last_install_date (the latest day anyone in this cohort actually
    -- installed) is the maturity anchor below — week_end alone would be
    -- too strict for the first cohort, whose week starts before the
    -- tracking window opens.
    SELECT
        cohort_year,
        cohort_week,
        MIN(cohort_week_start)                              AS week_start,
        MAX(cohort_week_end)                                AS week_end,
        MAX(install_date)                                   AS last_install_date,
        COUNT(DISTINCT user_id)                              AS cohort_size
    FROM cohort
    GROUP BY cohort_year, cohort_week
),
active AS (
    -- users still active on exactly day N after their own install_date
    SELECT
        c.cohort_year,
        c.cohort_week,
        a.days_since_install,
        COUNT(DISTINCT a.user_id)                            AS active_users
    FROM mart.fact_daily_activity a
    JOIN cohort c
        ON c.user_id = a.user_id
    GROUP BY c.cohort_year, c.cohort_week, a.days_since_install
)
SELECT
    cw.cohort_year,
    cw.cohort_week,
    CONVERT(VARCHAR(5), cw.week_start, 3) + N' – ' + CONVERT(VARCHAR(5), cw.week_end, 3) AS cohort_week_label,
    cw.cohort_size,
    dd.days_since_install,
    COALESCE(ac.active_users, 0)                              AS active_users,
    CAST(COALESCE(ac.active_users, 0) AS DECIMAL(10,4))
        / NULLIF(cw.cohort_size, 0)                            AS retention_pct
FROM cohort_week cw
CROSS JOIN mart.dim_days_since_install dd
CROSS JOIN last_tracked_date ltd
LEFT JOIN active ac
    ON ac.cohort_year = cw.cohort_year
   AND ac.cohort_week = cw.cohort_week
   AND ac.days_since_install = dd.days_since_install
-- the mature-cohort filter: emit a (cohort, day N) cell ONLY when every
-- user in that cohort has had the chance to reach day N by max_date.
-- Without it, cells for cohorts too young to have reached day N yet come
-- back as active_users = 0 (COALESCE above) rather than being absent,
-- which drags the whole curve down — the same defect that made the
-- D1/D7/D30 KPI cards read far below reality before they were fixed.
WHERE DATEADD(DAY, dd.days_since_install, cw.last_install_date) <= ltd.max_date;
GO

------------------------------------------------------------
-- Verify: row counts + sanity checks
------------------------------------------------------------
SELECT 'mart.fact_retention_curve' AS view_name, COUNT(*) AS row_count
FROM mart.fact_retention_curve;
GO

-- retention_pct should be 100% (1.0000) at days_since_install = 0 for
-- every cohort week - if not, the cohort/day-0 join above is off
SELECT cohort_year, cohort_week, cohort_week_label, retention_pct
FROM mart.fact_retention_curve
WHERE days_since_install = 0
  AND retention_pct <> 1.0000;
GO

-- retention_pct must never exceed 100% or go negative
SELECT *
FROM mart.fact_retention_curve
WHERE retention_pct > 1.0000 OR retention_pct < 0;
GO

-- Cross-check against the KPI cards: collapsing every cohort week into one
-- weighted figure per day-N must reproduce the D1/D7/D30 numbers that
-- mart.fact_retention_summary (and the Power BI cards) report. Expect
-- D1 ~27.3%, D7 ~8.1%, D30 ~3.6%. A plain AVG(retention_pct) here would
-- NOT match — cohort weeks differ wildly in size, so the curve must be
-- aggregated as SUM(active) / SUM(cohort), never as an average of ratios.
SELECT
    days_since_install,
    SUM(cohort_size)   AS cohort_size_total,
    SUM(active_users)  AS active_users_total,
    CAST(SUM(active_users) AS DECIMAL(10,4)) / NULLIF(SUM(cohort_size), 0) AS retention_pct_weighted
FROM mart.fact_retention_curve
WHERE days_since_install IN (1, 7, 30)
GROUP BY days_since_install
ORDER BY days_since_install;
GO

-- How many (cohort week x day N) cells the maturity filter removed, per
-- cohort — the youngest cohorts should lose the most days (they have not
-- lived long enough to be observed at the higher day-Ns yet)
SELECT
    cohort_week_label,
    MIN(cohort_size)              AS cohort_size,
    COUNT(*)                      AS days_kept,
    31 - COUNT(*)                 AS days_dropped_as_immature
FROM mart.fact_retention_curve
GROUP BY cohort_week_label, cohort_year, cohort_week
ORDER BY cohort_year, cohort_week;
GO
