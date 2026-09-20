# Product X — Analytics Project

Data pipeline, warehouse model and Power BI dashboard for Product X, covering the first two months of operation (1 June – 31 July 2023, ~128,700 installs).

The project answers three questions:

1. Build a dashboard the project team can use to monitor operations and spot problems.
2. Analyse product quality and user engagement, and recommend improvements.
3. Recommend a maximum CPI per traffic source, given that day-7 user value should cover acquisition cost.

---

## Repository layout

```
powerbi/      Dashboard file, theme, and DAX measure reference
docs/         Data quality documentation and dashboard design notes
DDL/          Earlier iteration of the schema scripts, kept for reference
```

Source CSV exports are **not** in this repository (see [Data](#data) below).

---

## Architecture

Three layers, each with a distinct job:

| Layer | Contents | Purpose |
|---|---|---|
| `raw` | One table per source CSV, all columns text | Faithful mirror of the source. Nothing cast, nothing dropped, so the original is always recoverable. |
| `dwh` | Conformed dimensions and fact tables | Correct types, duplicates removed, one shared user and date dimension. A star schema every fact joins back to. |
| `mart` | Views, plus the eCPM price table | The only layer Power BI reads. Page-specific logic lives here so report changes never touch the shared model. |

Power BI connects to `mart` alone. Heavier aggregations — cohort retention in particular — are pre-computed in SQL rather than in DAX, so the report stays responsive.

---

## Data

The seven source exports are excluded from version control: together they are around 300 MB, and `ad_impression.csv` alone exceeds GitHub's 100 MB file limit. Place them in the project root before running `02_import_raw_data.sql`.

| File | Rows | Grain |
|---|---:|---|
| `first_open.csv` | 136,324 | One per install |
| `session_start.csv` | 321,169 | One per user per day |
| `user_engagement.csv` | 322,708 | One per user per day |
| `main_function.csv` | 707,743 | One per feature use |
| `reminder.csv` | 459,974 | One per show / click / close |
| `ad_impression.csv` | 1,016,168 | One per impression |
| `app_remove.csv` | 70,625 | One per uninstall |

One input is not tracking data: the eCPM price table (market tier × ad format) is a business input, entered by hand in `06_build_mart.sql`. Every revenue and LTV figure rests on it, and is labelled as an estimate accordingly.

### The `dwh` layer — Data Warehouse

Physical tables (`TABLE`, built via `SELECT INTO` from `raw.*`), normalized star schema — every fact joins back to `dwh.dim_user` via `user_id`.

| Table | Grain | Source | Notes |
|---|---|---|---|
| `dwh.dim_date` | 1 row / calendar day | Generated via recursive CTE | Covers 2023-05-25 → 2023-08-07 (wider than the actual data window, for buffer). PK: `date_key`. |
| `dwh.dim_user` | 1 row / user | `raw.first_open_clean` (deduped) | Type-0 dimension — install-time attributes only, no evidence user attributes change over time. PK: `user_id`. NULL/blank `traffic_source_source` is mapped to `'unknown'`. |
| `dwh.fact_app_remove` | 1 row / user (uninstall event) | `raw.app_remove` | Kept as its own fact (not folded into `dim_user`) since it's an event with a date + a measure (`total_number_session_at_remove`). |
| `dwh.fact_session_daily` | 1 row / user / day | `raw.session_start`, SUMmed by `(user_id, event_date)` | Raw has multiple rows per user/day with differing `session_count` (multi-device/VPN pattern) — summed, not deduped away. |
| `dwh.fact_engagement_daily` | 1 row / user / day | `raw.user_engagement`, SUMmed by `(user_id, event_date)` | Same pattern as session_daily. `engagement_time_sec` kept as DECIMAL (seconds with decimals). |
| `dwh.fact_main_function` | 1 row / feature-usage event | `raw.main_function` | No aggregation — each event kept as-is. |
| `dwh.fact_reminder` | 1 row / show-click-close event | `raw.reminder` | Funnel by `remind_type` + `remind_position`. |
| `dwh.fact_ad_impression` | 1 row / ad impression | `raw.ad_impression_clean` (deduped) | `tier` backfilled from `dim_user.tier` when missing in raw (COALESCE); ~2,329 rows remain NULL because those users installed before the tracking window opened (left-censoring) — there's no way to recover their tier. |

Every fact carries `days_since_install = DATEDIFF(DAY, dim_user.install_date, event_date)`, pre-computed so it doesn't need to be re-derived in DAX. Casts from raw use `TRY_CAST` — a failed cast becomes NULL, the row is never dropped (failure rates were already verified as ~0 in step 03).

Indexes support dashboard-style filtering/joins: each fact has an index on `(user_id, event_date)` or `user_id`; `dim_user` has one on `(traffic_source_source, tier)`.

---

### The `mart` layer — Reporting (the only layer Power BI reads)

Mostly pass-through VIEWs or light joins on top of `dwh.*`, kept normalized (not denormalized) — Power BI Desktop builds the relationships itself after import.

| Object | Type | Source / logic | Notes |
|---|---|---|---|
| `mart.dim_user` | VIEW | Pass-through of `dwh.dim_user` | Shared dimension for every fact — a slicer on country/tier/traffic_source filters all facts automatically through the relationship. |
| `mart.dim_date` | VIEW | Pass-through of `dwh.dim_date` | |
| `mart.dim_ecpm` | TABLE | Hand-entered from the brief (question 3) | Keyed on `(tier, ad_format)`. Includes a sentinel `'unknown'` row for impressions with no recoverable tier, so they aren't dropped from revenue. |
| `mart.fact_daily_activity` | VIEW | FULL OUTER JOIN of `fact_session_daily` + `fact_engagement_daily` | Grain: 1 row / user / day. Unions two same-grain facts into one table so Overview/Engagement pages read from a single source. |
| `mart.fact_main_function` | VIEW | Pass-through of `dwh.fact_main_function` | |
| `mart.fact_reminder` | VIEW | Pass-through of `dwh.fact_reminder` | |
| `mart.fact_ad_impression` | VIEW | `dwh.fact_ad_impression` JOINed to `mart.dim_ecpm` | Pre-computes `est_revenue_usd = ecpm_usd / 1000` per row — Power BI just SUMs it, no lookup logic needed in DAX. |
| `mart.fact_app_remove` | VIEW | Pass-through of `dwh.fact_app_remove` | |

Design principle: page-specific logic (e.g. unioning session+engagement, or joining in eCPM) lives in the `mart` layer, so changing a report never touches the shared model in `dwh`.

---

## Measuring retention

Retention is cohort-based: each user is evaluated against **their own** install date, and only once enough days have passed for that measurement to be possible.

This second condition matters. A user who installed on 30 July cannot have a day-7 data point when the data ends on 31 July — counting them in the denominator understates retention, and the distortion grows with N. Every retention measure here, in SQL and in DAX, excludes users whose install date is less than N days before the last tracked date.

Aggregation across cohorts is weighted — `SUM(active) / SUM(cohort)`, never an average of per-cohort ratios. Cohort sizes vary by more than an order of magnitude, so an unweighted average gives a materially different and incorrect answer.

---

## Data quality

`03_data_quality_check.sql` covers duplicates, missing values, cross-table consistency, chronological validity, date coverage and categorical validity.

One material issue was found: `first_open` (5.55% of rows) and `ad_impression` (3.14%) contained exact duplicates matching to the microsecond — a tracking retry artefact, not user behaviour. These are removed in `04_dedupe_raw.sql`. Left in place, they would inflate both install counts and ad revenue.

A known limitation remains: users who installed before 1 June fall outside the tracking window but still appear when they uninstall. This inflates uninstall rates for very small markets, so country-level rates should use a minimum volume threshold.

Full detail in `docs/data_quality_summary.md` (written for a general audience) and `docs/data_quality_log_technical.md` (SQL-level trace).

---

## Dashboard

`powerbi/iKame_dashboard.pbix` — five pages, ordered from overview to detail:

1. **Executive Overview** — headline KPIs and trend
2. **Acquisition & Growth** — sources, markets, versions, weekly volume-versus-quality
3. **Engagement & Product Health** — feature adoption, session depth, reminder effectiveness
4. **Retention & Churn** — retention curve, uninstall timing, churn by session count
5. **Monetization (IAA)** — impressions, eCPM, LTV D7 and CPI guidance

Every page carries the same four slicers — date, country, tier, traffic source — applied through the shared user dimension.

`powerbi/ikame_theme.json` holds the colour theme.

## AI Usage

AI (Claude) was used throughout this project as a collaborator - every suggestion below was verified against the actual data before being kept.

**Metrics & analysis depth**
- Suggested additional cuts beyond the brief's minimum ask — e.g. retention broken down by cohort week *and* by dimension, to surface whether retention problems are concentrated in specific countries/tiers/sources rather than uniform.
- Flagged that an unweighted average of per-cohort retention rates would be statistically wrong given cohort sizes vary by more than an order of magnitude, and confirmed thet) weighting fix.

**ETL debugging**
- Helped diagnose why `first_open` and `ad_impression` row counts didn't match expected install/impression volumes — traced to exact-duplicate rows matching to the microsecond, identified as a tracking retry artefact rather than real user behavior (documented in `docs/data_quality_log_technical.md`), which led to the dedupe step.
- Helped investigate why `session_start` and `user_engagement` had more rows than expected per `(user_id, event_date)` — found genuinely differing `session_count`/`engagement_time` values per row (multi-device/VPN pattern), which ruled out a simple dedupe and led to the SUM-by-day aggregation used in `dwh.fact_session_daily` / `dwh.fact_engagement_daily`.
- Helped trace the ~2,300 `ad_impression` rows with NULL `tier` back to users who installed before the tracking window opened (left-censored), rather than a data entry error — leading to the partial COALESCE backfill from `dim_user.tier` and the `'unknown'` sentinel row in `mart.dim_ecpm`, instead of silently dropping that revenue.

**Dashboard & slide design**
- Reviewed the page structure (Overview → Acquisition → Engagement → Retention → Monetization) for narrative flow, and suggested keeping heavy aggregations (retention curve) pre-computed in SQL rather than DAX so the report stays responsive.
- Assisted with DAX measure wording/logic in `powerbi/dax_measures.md`, in particular the "exclude cohorts too young to have reached day-N" guard, which is easy to get subtly wrong in DAX filter context.
- Helped structure the presentation slides — narrowing findings down to the ones that are decision-relevant (e.g. the CPI recommendation) rather than restating every chart on the dashboard.


