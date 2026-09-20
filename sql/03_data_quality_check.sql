/* ============================================================
   03_data_quality_check.sql
   Purpose : Profile raw.* tables before modeling into dwh.
             Checks: row counts, null/blank rates, duplicates,
             referential integrity vs. first_open (user dimension),
             date range sanity, categorical value sanity,
             numeric castability.
   Run after: 02_import_raw_data.sql
   ============================================================ */

USE data_test;
GO

------------------------------------------------------------
-- 1. Row counts per table (compare against source wc -l)
------------------------------------------------------------
SELECT 'first_open' AS table_name, COUNT(*) AS row_count FROM raw.first_open
UNION ALL SELECT 'session_start',   COUNT(*) FROM raw.session_start
UNION ALL SELECT 'user_engagement', COUNT(*) FROM raw.user_engagement
UNION ALL SELECT 'main_function',   COUNT(*) FROM raw.main_function
UNION ALL SELECT 'reminder',        COUNT(*) FROM raw.reminder
UNION ALL SELECT 'ad_impression',   COUNT(*) FROM raw.ad_impression
UNION ALL SELECT 'app_remove',      COUNT(*) FROM raw.app_remove;
GO

------------------------------------------------------------
-- 2. Duplicate check — FULL-ROW duplicates only.
--    Repeats of just user_id (or user_id+date) are NOT flagged as
--    errors here: a user can uninstall and reinstall (new first_open),
--    or legitimately have multiple sessions/engagement rows on the
--    same day depending on how the source aggregates. Only a row
--    that matches another row on EVERY business column is treated
--    as a duplicate (event double-fired / double-logged).
--    (_load_ts / _source_file excluded — always differ per load.)
------------------------------------------------------------

-- 2a. first_open: full-row duplicates
SELECT event_date, event_timestamp, user_id, app_version, country, tier, city,
       language, operating_system_version, mobile_brand_name, mobile_marketing_name,
       traffic_source_source, COUNT(*) AS n
FROM raw.first_open
GROUP BY event_date, event_timestamp, user_id, app_version, country, tier, city,
         language, operating_system_version, mobile_brand_name, mobile_marketing_name,
         traffic_source_source
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2b. app_remove: full-row duplicates
SELECT event_date, user_id, app_version, country, tier, city,
       params_total_number_session, COUNT(*) AS n
FROM raw.app_remove
GROUP BY event_date, user_id, app_version, country, tier, city, params_total_number_session
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2c. session_start: full-row duplicates
SELECT event_date, user_id, app_version, country, tier, city, event_count, COUNT(*) AS n
FROM raw.session_start
GROUP BY event_date, user_id, app_version, country, tier, city, event_count
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2d. user_engagement: full-row duplicates
SELECT event_date, user_id, app_version, country, tier, city, engagement_time, COUNT(*) AS n
FROM raw.user_engagement
GROUP BY event_date, user_id, app_version, country, tier, city, engagement_time
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2e. main_function: full-row duplicates
SELECT event_date, event_timestamp, event_name, user_id, app_version, country,
       params_total_number_session, action_type, function_name, COUNT(*) AS n
FROM raw.main_function
GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
         params_total_number_session, action_type, function_name
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2f. reminder: full-row duplicates
SELECT event_date, event_timestamp, event_name, user_id, app_version, country,
       params_total_number_session, params_remind_type, params_remind_position,
       params_action_name, COUNT(*) AS n
FROM raw.reminder
GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
         params_total_number_session, params_remind_type, params_remind_position,
         params_action_name
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- 2g. ad_impression: full-row duplicates
SELECT event_date, event_timestamp, event_name, user_id, app_version, country,
       tier, params_ad_format, COUNT(*) AS n
FROM raw.ad_impression
GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
         tier, params_ad_format
HAVING COUNT(*) > 1
ORDER BY n DESC;
GO

------------------------------------------------------------
-- 2h. Summary: total full-row duplicate rows per table
--     (sum of (n-1) across dup groups = rows to remove if deduped)
------------------------------------------------------------
;WITH fo AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, event_timestamp, user_id, app_version,
           country, tier, city, language, operating_system_version, mobile_brand_name,
           mobile_marketing_name, traffic_source_source)) AS extra_rows
    FROM raw.first_open
),
ar AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, user_id, app_version, country, tier, city, params_total_number_session)) AS extra_rows
    FROM raw.app_remove
),
ss AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, user_id, app_version, country, tier, city, event_count)) AS extra_rows
    FROM raw.session_start
),
ue AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, user_id, app_version, country, tier, city, engagement_time)) AS extra_rows
    FROM raw.user_engagement
),
mf AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, event_timestamp, event_name, user_id, app_version, country, params_total_number_session, action_type, function_name)) AS extra_rows
    FROM raw.main_function
),
rm AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, event_timestamp, event_name, user_id, app_version, country, params_total_number_session, params_remind_type, params_remind_position, params_action_name)) AS extra_rows
    FROM raw.reminder
),
ai AS (
    SELECT COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', event_date, event_timestamp, event_name, user_id, app_version, country, tier, params_ad_format)) AS extra_rows
    FROM raw.ad_impression
)
SELECT 'first_open' AS table_name, extra_rows FROM fo
UNION ALL SELECT 'app_remove', extra_rows FROM ar
UNION ALL SELECT 'session_start', extra_rows FROM ss
UNION ALL SELECT 'user_engagement', extra_rows FROM ue
UNION ALL SELECT 'main_function', extra_rows FROM mf
UNION ALL SELECT 'reminder', extra_rows FROM rm
UNION ALL SELECT 'ad_impression', extra_rows FROM ai;
GO

------------------------------------------------------------
-- 2i. INVESTIGATE first_open duplicates
--     Goal: is this "reinstall" (different event_timestamp, same
--     user_id) or "true dup" (literally every column identical,
--     including event_timestamp — a tracking re-fire, not a real event)?
------------------------------------------------------------

-- How many groups repeat 2x vs 3x vs more? (a real reinstall pattern
-- would rarely repeat the SAME row 3+ times; a client-side retry bug
-- often fires the exact same event 2x back-to-back)
SELECT dup_count, COUNT(*) AS n_groups
FROM (
    SELECT event_date, event_timestamp, user_id, app_version, country, tier, city,
           language, operating_system_version, mobile_brand_name, mobile_marketing_name,
           traffic_source_source, COUNT(*) AS dup_count
    FROM raw.first_open
    GROUP BY event_date, event_timestamp, user_id, app_version, country, tier, city,
             language, operating_system_version, mobile_brand_name, mobile_marketing_name,
             traffic_source_source
    HAVING COUNT(*) > 1
) t
GROUP BY dup_count
ORDER BY dup_count;

-- Does this user_id have MULTIPLE DISTINCT event_timestamps too
-- (true reinstall = new timestamp each time) or only ONE timestamp
-- repeated N times (= same event logged N times = tracking bug)?
SELECT
    reinstall_pattern = CASE WHEN distinct_timestamps > 1 THEN 'multiple distinct timestamps (looks like reinstall)'
                              ELSE 'single timestamp repeated (looks like duplicate firing)' END,
    COUNT(*) AS n_users
FROM (
    SELECT user_id, COUNT(DISTINCT event_timestamp) AS distinct_timestamps
    FROM raw.first_open
    GROUP BY user_id
    HAVING COUNT(*) > 1   -- users with >1 total row
) t
GROUP BY CASE WHEN distinct_timestamps > 1 THEN 'multiple distinct timestamps (looks like reinstall)'
              ELSE 'single timestamp repeated (looks like duplicate firing)' END;

-- Sample 20 actual duplicate rows to eyeball
SELECT TOP 20 *
FROM raw.first_open f
WHERE EXISTS (
    SELECT 1 FROM raw.first_open f2
    WHERE f2.user_id = f.user_id AND f2.event_timestamp = f.event_timestamp
      AND f2.event_date = f.event_date
    GROUP BY f2.user_id, f2.event_timestamp, f2.event_date
    HAVING COUNT(*) > 1
)
ORDER BY f.user_id, f.event_timestamp;

-- If a user_id has rows spanning MULTIPLE event_date values
-- (not just duplicate timestamps), that's a strong reinstall signal
SELECT
    COUNT(DISTINCT user_id) AS users_with_multiple_install_dates
FROM (
    SELECT user_id
    FROM raw.first_open
    GROUP BY user_id
    HAVING COUNT(DISTINCT event_date) > 1
) t;
GO

------------------------------------------------------------
-- 2j. INVESTIGATE ad_impression duplicates
--     Goal: same check — genuinely repeated events (same user,
--     same microsecond timestamp, same ad_format) vs. legitimate
--     rapid back-to-back impressions with distinct timestamps.
------------------------------------------------------------

SELECT dup_count, COUNT(*) AS n_groups
FROM (
    SELECT event_date, event_timestamp, event_name, user_id, app_version, country,
           tier, params_ad_format, COUNT(*) AS dup_count
    FROM raw.ad_impression
    GROUP BY event_date, event_timestamp, event_name, user_id, app_version, country,
             tier, params_ad_format
    HAVING COUNT(*) > 1
) t
GROUP BY dup_count
ORDER BY dup_count;

-- Sample 20 actual duplicate rows to eyeball
SELECT TOP 20 *
FROM raw.ad_impression a
WHERE EXISTS (
    SELECT 1 FROM raw.ad_impression a2
    WHERE a2.user_id = a.user_id AND a2.event_timestamp = a.event_timestamp
      AND a2.params_ad_format = a.params_ad_format
    GROUP BY a2.user_id, a2.event_timestamp, a2.params_ad_format
    HAVING COUNT(*) > 1
)
ORDER BY a.user_id, a.event_timestamp;

-- Are duplicates concentrated on specific dates (systemic tracking
-- bug on a bad app_version/day) or spread evenly (random noise)?
SELECT event_date, COUNT(*) AS dup_row_count
FROM (
    SELECT event_date, event_timestamp, event_name, user_id, app_version, country,
           tier, params_ad_format,
           COUNT(*) OVER (PARTITION BY event_date, event_timestamp, event_name, user_id,
                           app_version, country, tier, params_ad_format) AS dup_count
    FROM raw.ad_impression
) t
WHERE dup_count > 1
GROUP BY event_date
ORDER BY dup_row_count DESC;

-- Are duplicates concentrated on specific app_version (client bug)?
SELECT app_version, COUNT(*) AS dup_row_count
FROM (
    SELECT app_version, event_date, event_timestamp, event_name, user_id, country,
           tier, params_ad_format,
           COUNT(*) OVER (PARTITION BY event_date, event_timestamp, event_name, user_id,
                           app_version, country, tier, params_ad_format) AS dup_count
    FROM raw.ad_impression
) t
WHERE dup_count > 1
GROUP BY app_version
ORDER BY dup_row_count DESC;
GO

------------------------------------------------------------
-- 3. Null / blank rate per key column, per table
------------------------------------------------------------
SELECT 'first_open' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)              AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(event_date)), '') IS NULL THEN 1 ELSE 0 END)           AS null_event_date,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(country)), '') IS NULL THEN 1 ELSE 0 END)              AS null_country,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(tier)), '') IS NULL THEN 1 ELSE 0 END)                 AS null_tier,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(traffic_source_source)), '') IS NULL THEN 1 ELSE 0 END) AS null_traffic_source,
    COUNT(*) AS total_rows
FROM raw.first_open;

SELECT 'session_start' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)    AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(event_date)), '') IS NULL THEN 1 ELSE 0 END) AS null_event_date,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(event_count)), '') IS NULL THEN 1 ELSE 0 END) AS null_event_count,
    COUNT(*) AS total_rows
FROM raw.session_start;

SELECT 'user_engagement' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)         AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(engagement_time)), '') IS NULL THEN 1 ELSE 0 END) AS null_engagement_time,
    COUNT(*) AS total_rows
FROM raw.user_engagement;

SELECT 'main_function' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)       AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(function_name)), '') IS NULL THEN 1 ELSE 0 END) AS null_function_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(action_type)), '') IS NULL THEN 1 ELSE 0 END)   AS null_action_type,
    COUNT(*) AS total_rows
FROM raw.main_function;

SELECT 'reminder' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)            AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(params_remind_type)), '') IS NULL THEN 1 ELSE 0 END) AS null_remind_type,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(params_action_name)), '') IS NULL THEN 1 ELSE 0 END) AS null_action_name,
    COUNT(*) AS total_rows
FROM raw.reminder;

SELECT 'ad_impression' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END)          AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(tier)), '') IS NULL THEN 1 ELSE 0 END)             AS null_tier,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(params_ad_format)), '') IS NULL THEN 1 ELSE 0 END) AS null_ad_format,
    COUNT(*) AS total_rows
FROM raw.ad_impression;

SELECT 'app_remove' AS table_name,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(user_id)), '') IS NULL THEN 1 ELSE 0 END) AS null_user_id,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(tier)), '') IS NULL THEN 1 ELSE 0 END)    AS null_tier,
    COUNT(*) AS total_rows
FROM raw.app_remove;
GO

------------------------------------------------------------
-- 4. Referential integrity: every user_id in other tables
--    should exist in first_open (the user acquisition dimension).
--    Orphans = users active/engaging/uninstalling without a
--    recorded install event (could be install before data window,
--    tracking gap, or app reinstall).
------------------------------------------------------------
SELECT 'session_start orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.session_start s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;

SELECT 'user_engagement orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.user_engagement s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;

SELECT 'main_function orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.main_function s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;

SELECT 'reminder orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.reminder s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;

SELECT 'ad_impression orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.ad_impression s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;

SELECT 'app_remove orphans' AS check_name, COUNT(DISTINCT s.user_id) AS orphan_users
FROM raw.app_remove s
LEFT JOIN raw.first_open f ON f.user_id = s.user_id
WHERE f.user_id IS NULL;
GO

------------------------------------------------------------
-- 5. Logical consistency: event_date should not be before
--    the user's first_open date (event before install = bug)
------------------------------------------------------------
SELECT 'session_start before install' AS check_name, COUNT(*) AS bad_rows
FROM raw.session_start s
JOIN raw.first_open f ON f.user_id = s.user_id
WHERE TRY_CAST(s.event_date AS DATE) < TRY_CAST(f.event_date AS DATE);

SELECT 'user_engagement before install' AS check_name, COUNT(*) AS bad_rows
FROM raw.user_engagement s
JOIN raw.first_open f ON f.user_id = s.user_id
WHERE TRY_CAST(s.event_date AS DATE) < TRY_CAST(f.event_date AS DATE);

SELECT 'app_remove before install' AS check_name, COUNT(*) AS bad_rows
FROM raw.app_remove s
JOIN raw.first_open f ON f.user_id = s.user_id
WHERE TRY_CAST(s.event_date AS DATE) < TRY_CAST(f.event_date AS DATE);
GO

------------------------------------------------------------
-- 6. Date range sanity — expect 2023-06-01 .. 2023-07-31 (per source files)
--    Flag anything outside this window per table.
------------------------------------------------------------
SELECT 'first_open' AS table_name, MIN(TRY_CAST(event_date AS DATE)) AS min_date, MAX(TRY_CAST(event_date AS DATE)) AS max_date,
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END) AS unparseable_dates
FROM raw.first_open
UNION ALL
SELECT 'session_start', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.session_start
UNION ALL
SELECT 'user_engagement', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.user_engagement
UNION ALL
SELECT 'main_function', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.main_function
UNION ALL
SELECT 'reminder', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.reminder
UNION ALL
SELECT 'ad_impression', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.ad_impression
UNION ALL
SELECT 'app_remove', MIN(TRY_CAST(event_date AS DATE)), MAX(TRY_CAST(event_date AS DATE)),
       SUM(CASE WHEN TRY_CAST(event_date AS DATE) IS NULL THEN 1 ELSE 0 END)
FROM raw.app_remove;
GO

------------------------------------------------------------
-- 7. Categorical value sanity — confirm expected value sets
--    (flag unexpected categories that might indicate tracking bugs)
------------------------------------------------------------
SELECT 'tier' AS field, tier AS value, COUNT(*) AS n FROM raw.first_open GROUP BY tier ORDER BY n DESC;
SELECT 'traffic_source_source' AS field, traffic_source_source AS value, COUNT(*) AS n FROM raw.first_open GROUP BY traffic_source_source ORDER BY n DESC;
SELECT 'params_ad_format' AS field, params_ad_format AS value, COUNT(*) AS n FROM raw.ad_impression GROUP BY params_ad_format ORDER BY n DESC;
SELECT 'action_type' AS field, action_type AS value, COUNT(*) AS n FROM raw.main_function GROUP BY action_type ORDER BY n DESC;
SELECT 'function_name' AS field, function_name AS value, COUNT(*) AS n FROM raw.main_function GROUP BY function_name ORDER BY n DESC;
SELECT 'params_remind_type' AS field, params_remind_type AS value, COUNT(*) AS n FROM raw.reminder GROUP BY params_remind_type ORDER BY n DESC;
SELECT 'params_action_name' AS field, params_action_name AS value, COUNT(*) AS n FROM raw.reminder GROUP BY params_action_name ORDER BY n DESC;
GO

------------------------------------------------------------
-- 8. Numeric castability — verify numeric-looking text columns
--    actually convert cleanly (0 bad_rows expected; else inspect)
------------------------------------------------------------
SELECT 'session_start.event_count' AS field,
       SUM(CASE WHEN TRY_CAST(event_count AS INT) IS NULL AND NULLIF(LTRIM(RTRIM(event_count)),'') IS NOT NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.session_start;

SELECT 'user_engagement.engagement_time' AS field,
       SUM(CASE WHEN TRY_CAST(engagement_time AS DECIMAL(18,3)) IS NULL AND NULLIF(LTRIM(RTRIM(engagement_time)),'') IS NOT NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.user_engagement;

SELECT 'main_function.params_total_number_session' AS field,
       SUM(CASE WHEN TRY_CAST(params_total_number_session AS INT) IS NULL AND NULLIF(LTRIM(RTRIM(params_total_number_session)),'') IS NOT NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.main_function;

SELECT 'app_remove.params_total_number_session' AS field,
       SUM(CASE WHEN TRY_CAST(params_total_number_session AS INT) IS NULL AND NULLIF(LTRIM(RTRIM(params_total_number_session)),'') IS NOT NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.app_remove;
GO

------------------------------------------------------------
-- 9. event_timestamp unit check (expect microseconds since epoch,
--    ~16 digits for 2023 dates) — flag rows that don't fit
------------------------------------------------------------
SELECT 'first_open.event_timestamp' AS field,
       MIN(LEN(event_timestamp)) AS min_len, MAX(LEN(event_timestamp)) AS max_len,
       SUM(CASE WHEN TRY_CAST(event_timestamp AS BIGINT) IS NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.first_open;

SELECT 'ad_impression.event_timestamp' AS field,
       MIN(LEN(event_timestamp)) AS min_len, MAX(LEN(event_timestamp)) AS max_len,
       SUM(CASE WHEN TRY_CAST(event_timestamp AS BIGINT) IS NULL THEN 1 ELSE 0 END) AS bad_rows
FROM raw.ad_impression;
GO
