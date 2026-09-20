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
-- Step 1: drop full-row duplicates (confirmed tracking re-fires —
-- same event, same everything, see docs/data_quality_log.md).
--
-- Step 2: a residual case was found AFTER step 1 — some users
-- still have 2+ rows that are identical on every column EXCEPT
-- the geo fields (city, and in a further sub-case, country/tier
-- too). Same user_id, same event_date, same event_timestamp to
-- the microsecond, same app_version/language/os/brand/traffic_source
-- — two installs cannot share the same microsecond timestamp, so
-- this is the SAME install event with inconsistent geo resolution
-- (IP geolocation / VPN artifacts): one sample case showed
-- country=India/tier=Tier04/city=Hapur vs. country=United
-- States/tier=Tier01/city=NULL for the identical event — the
-- NULL-city row is the less trustworthy one (coarse geolocation,
-- likely a VPN/proxy exit IP), so it is de-prioritized.
-- Business key excludes all 3 geo columns; tie-break keeps the
-- row with a non-NULL city (more precise geolocation) first.
------------------------------------------------------------
IF OBJECT_ID('raw.first_open_clean', 'U') IS NOT NULL DROP TABLE raw.first_open_clean;

WITH step1_full_row_dedupe AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY event_date, event_timestamp, user_id, app_version, country, tier,
                         city, language, operating_system_version, mobile_brand_name,
                         mobile_marketing_name, traffic_source_source
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM raw.first_open
),
step2_geo_inconsistency_dedupe AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY event_date, event_timestamp, user_id, app_version,
                         language, operating_system_version, mobile_brand_name,
                         mobile_marketing_name, traffic_source_source
            ORDER BY CASE WHEN city IS NOT NULL THEN 0 ELSE 1 END, city
        ) AS rn2
    FROM step1_full_row_dedupe
    WHERE rn = 1
)
SELECT event_date, event_timestamp, user_id, app_version, country, tier, city,
       language, operating_system_version, mobile_brand_name, mobile_marketing_name,
       traffic_source_source
INTO raw.first_open_clean
FROM step2_geo_inconsistency_dedupe
WHERE rn2 = 1;
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
    SELECT 1 AS dummy
    FROM raw.first_open_clean
    GROUP BY event_date, event_timestamp, user_id, app_version, country, tier, city,
             language, operating_system_version, mobile_brand_name, mobile_marketing_name,
             traffic_source_source
    HAVING COUNT(*) > 1
) t;

SELECT 'ad_impression_clean remaining dups' AS check_name, COUNT(*) AS n
FROM (
    SELECT 1 AS dummy
    FROM raw.ad_impression_clean
    GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
             tier, params_ad_format
    HAVING COUNT(*) > 1
) t;

-- first_open_clean must now be exactly 1 row per user_id
-- (required: dwh.dim_user uses user_id as primary key)
SELECT 'first_open_clean users with >1 row (should be 0)' AS check_name, COUNT(*) AS n
FROM (
    SELECT user_id
    FROM raw.first_open_clean
    GROUP BY user_id
    HAVING COUNT(*) > 1
) t;
GO
