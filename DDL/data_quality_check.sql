------------------------------------------------------------
WITH fo AS (
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

-----------------------------------------------------------
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
