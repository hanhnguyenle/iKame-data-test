/* ============================================================
   09_build_retention_by_dimension.sql
   Purpose : Same "mature cohort" fix as 08_build_retention_summary.sql,
             but broken out by dimension (country, tier,
             traffic_source_source, cohort install week) instead of
             1 flat row — so every chart that slices D1/D7/D30
             Retention by a dimension (Acquisition page's "by
             traffic_source_source", Retention page's "by tier",
             Weekly Trend table's "by cohort week") reads pre-agged,
             correct numbers with a plain SUM/DIVIDE in Power BI —
             no DAX, no USERELATIONSHIP, no per-N cohort logic.

   Key idea (unchanged from 08): a user is only counted in the D-N
   cohort (both denominator and numerator) if their install_date is
   at least N days before the last tracked date — otherwise they
   have not had time to reach day N yet, and including them
   artificially deflates the ratio (this was the root cause of the
   D7/D30 KPI cards reading far lower than reality).

   Grain   : 1 row per (country, tier, traffic_source_source,
             cohort_year, cohort_week, N) where N in {1, 7, 30} —
             a "long" / unpivoted shape (one column `retention_day`
             holds 1/7/30, one row per N) rather than 3 wide columns,
             so Power BI can slice by ANY subset of the 4 dimensions
             (e.g. "by traffic_source_source only" = SUM grouping by
             traffic_source_source and retention_day, ignoring
             country/tier/cohort_week) using plain aggregation.

   Run after: 06_build_mart.sql, 07_build_retention_curve.sql
               (reuses the same cohort_week logic as 07, so the two
               stay consistent with each other)
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- MART.FACT_RETENTION_BY_DIMENSION
------------------------------------------------------------
IF OBJECT_ID('mart.fact_retention_by_dimension', 'V') IS NOT NULL DROP VIEW mart.fact_retention_by_dimension;
GO
CREATE VIEW mart.fact_retention_by_dimension AS
WITH last_tracked_date AS (
    SELECT MAX(event_date) AS max_date FROM mart.fact_daily_activity
),
cohort AS (
    -- 1 row per user, tagged with every dimension a chart might
    -- slice retention by, plus the Mon-Sun cohort week (reusing the
    -- same convention as mart.fact_retention_curve)
    SELECT
        u.user_id,
        u.install_date,
        u.country,
        u.tier,
        u.traffic_source_source,
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
-- N=1/7/30 as a small inline table instead of 3 copy-pasted blocks
retention_day AS (
    SELECT retention_day FROM (VALUES (1), (7), (30)) v(retention_day)
),
cohort_mature AS (
    -- 1 row per (user, N) — only kept if the user's install_date is
    -- old enough for day-N to have been observable by max_date
    SELECT
        c.*,
        rd.retention_day
    FROM cohort c
    CROSS JOIN retention_day rd
    CROSS JOIN last_tracked_date ltd
    WHERE c.install_date <= DATEADD(DAY, -rd.retention_day, ltd.max_date)
),
active AS (
    -- users active on EXACTLY day N after their own install_date
    SELECT DISTINCT
        a.user_id,
        a.days_since_install AS retention_day
    FROM mart.fact_daily_activity a
    WHERE a.days_since_install IN (1, 7, 30)
)
SELECT
    cm.country,
    cm.tier,
    cm.traffic_source_source,
    cm.cohort_year,
    cm.cohort_week,
    CONVERT(VARCHAR(5), cm.cohort_week_start, 3) + N' – ' + CONVERT(VARCHAR(5), cm.cohort_week_end, 3) AS cohort_week_label,
    cm.retention_day,
    COUNT(DISTINCT cm.user_id)                                            AS cohort_size,
    COUNT(DISTINCT CASE WHEN ac.user_id IS NOT NULL THEN cm.user_id END)  AS active_users,
    CAST(COUNT(DISTINCT CASE WHEN ac.user_id IS NOT NULL THEN cm.user_id END) AS DECIMAL(10,4))
        / NULLIF(COUNT(DISTINCT cm.user_id), 0)                          AS retention_pct
FROM cohort_mature cm
LEFT JOIN active ac
    ON ac.user_id = cm.user_id AND ac.retention_day = cm.retention_day
GROUP BY
    cm.country, cm.tier, cm.traffic_source_source,
    cm.cohort_year, cm.cohort_week, cm.cohort_week_start, cm.cohort_week_end,
    cm.retention_day;
GO

------------------------------------------------------------
-- Verify
------------------------------------------------------------
SELECT 'mart.fact_retention_by_dimension' AS view_name, COUNT(*) AS row_count
FROM mart.fact_retention_by_dimension;
GO

-- Re-derive the flat D1/D7/D30 totals from this view (collapsing
-- country/tier/traffic_source_source/cohort_week) and compare
-- against 08_build_retention_summary.sql's output — the two MUST
-- match exactly, since both apply the same mature-cohort filter
SELECT
    retention_day,
    SUM(cohort_size)  AS cohort_size_total,
    SUM(active_users) AS active_users_total,
    CAST(SUM(active_users) AS DECIMAL(10,4)) / NULLIF(SUM(cohort_size), 0) AS retention_pct_total
FROM mart.fact_retention_by_dimension
GROUP BY retention_day
ORDER BY retention_day;
GO

-- Sanity: retention_pct must be between 0 and 1 everywhere
SELECT *
FROM mart.fact_retention_by_dimension
WHERE retention_pct > 1.0000 OR retention_pct < 0;
GO

-- Sanity: by traffic_source_source only (collapsing country/tier/week) —
-- this is the shape the Acquisition page's "D1/D7/D30 Retention by
-- traffic_source_source" chart should now read from
SELECT
    traffic_source_source,
    retention_day,
    SUM(cohort_size)  AS cohort_size,
    SUM(active_users) AS active_users,
    CAST(SUM(active_users) AS DECIMAL(10,4)) / NULLIF(SUM(cohort_size), 0) AS retention_pct
FROM mart.fact_retention_by_dimension
GROUP BY traffic_source_source, retention_day
ORDER BY traffic_source_source, retention_day;
GO

-- Sanity: by tier only — this is the shape the Retention page's
-- "Tier / D1 / D7 / D30 Retention" table should now read from
SELECT
    tier,
    retention_day,
    SUM(cohort_size)  AS cohort_size,
    SUM(active_users) AS active_users,
    CAST(SUM(active_users) AS DECIMAL(10,4)) / NULLIF(SUM(cohort_size), 0) AS retention_pct
FROM mart.fact_retention_by_dimension
GROUP BY tier, retention_day
ORDER BY tier, retention_day;
GO
