/* ============================================================
   04_dedupe_raw.sql
   Purpose : Remove full-row duplicates found in raw.first_open
             and raw.ad_impression, WITHOUT touching the original
             raw tables (kept as-is for audit/traceability).
             Output goes to new *_clean tables, which downstream
             dwh views should read from instead of the raw originals.
   Basis   : see docs/data_quality_log.md — duplicates confirmed
             as true tracking re-fires (identical down to the
             microsecond event_timestamp), not legitimate repeat
             events (e.g. reinstall).
   Run after: 03_data_quality_check.sql
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- raw.first_open_clean
-- Keep 1 row per full business-key group. Rows within a group
-- are identical on every business column by definition (that's
-- why they were flagged as duplicates), so the tie-break order
-- does not matter — (SELECT NULL) is used instead of ordering
-- by a load-timestamp column, since not all environments have
-- one (e.g. tables created via SSMS Import Flat File wizard).
------------------------------------------------------------
IF OBJECT_ID('raw.first_open_clean', 'U') IS NOT NULL DROP TABLE raw.first_open_clean;

WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY event_date, event_timestamp, user_id, app_version, country, tier,
                         city, language, operating_system_version, mobile_brand_name,
                         mobile_marketing_name, traffic_source_source
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM raw.first_open
)
SELECT event_date, event_timestamp, user_id, app_version, country, tier, city,
       language, operating_system_version, mobile_brand_name, mobile_marketing_name,
       traffic_source_source
INTO raw.first_open_clean
FROM ranked
WHERE rn = 1;
GO

------------------------------------------------------------
-- raw.ad_impression_clean
------------------------------------------------------------
IF OBJECT_ID('raw.ad_impression_clean', 'U') IS NOT NULL DROP TABLE raw.ad_impression_clean;

WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY event_date, event_timestamp, event_name, user_id, app_version,
                         country, tier, params_ad_format
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM raw.ad_impression
)
SELECT event_date, event_timestamp, event_name, user_id, app_version, country, tier,
       params_ad_format
INTO raw.ad_impression_clean
FROM ranked
WHERE rn = 1;
GO

------------------------------------------------------------
-- Verify: before / after row counts + rows removed
------------------------------------------------------------
SELECT
    'first_open' AS table_name,
    (SELECT COUNT(*) FROM raw.first_open)       AS rows_before,
    (SELECT COUNT(*) FROM raw.first_open_clean) AS rows_after,
    (SELECT COUNT(*) FROM raw.first_open) - (SELECT COUNT(*) FROM raw.first_open_clean) AS rows_removed
UNION ALL
SELECT
    'ad_impression',
    (SELECT COUNT(*) FROM raw.ad_impression),
    (SELECT COUNT(*) FROM raw.ad_impression_clean),
    (SELECT COUNT(*) FROM raw.ad_impression) - (SELECT COUNT(*) FROM raw.ad_impression_clean);
GO

------------------------------------------------------------
-- Sanity: confirm zero full-row duplicates remain in *_clean
------------------------------------------------------------
SELECT 'first_open_clean remaining dups' AS check_name, COUNT(*) AS n
FROM (
    SELECT 1
    FROM raw.first_open_clean
    GROUP BY event_date, event_timestamp, user_id, app_version, country, tier, city,
             language, operating_system_version, mobile_brand_name, mobile_marketing_name,
             traffic_source_source
    HAVING COUNT(*) > 1
);

SELECT 'ad_impression_clean remaining dups' AS check_name, COUNT(*) AS n
FROM (
    SELECT 1
    FROM raw.ad_impression_clean
    GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
             tier, params_ad_format
    HAVING COUNT(*) > 1
) t;
GO
