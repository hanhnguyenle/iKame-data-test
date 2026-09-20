# Product X — Analytics Project

Data pipeline, warehouse model and Power BI dashboard for Product X, covering the first two months of operation (1 June – 31 July 2023, ~128,700 installs).

The project answers three questions:

1. Build a dashboard the project team can use to monitor operations and spot problems.
2. Analyse product quality and user engagement, and recommend improvements.
3. Recommend a maximum CPI per traffic source, given that day-7 user value should cover acquisition cost.

---

## Repository layout

```
sql/          Pipeline scripts, numbered in execution order
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

## Running the pipeline

Scripts run in numerical order against a SQL Server database named `data_test`.

| Script | What it does |
|---|---|
| `01_create_schema_and_raw_tables.sql` | Creates the three schemas and the raw tables |
| `01b_add_mart_schema.sql` | Adds the mart schema if missing |
| `02_import_raw_data.sql` | Loads the CSV exports into raw |
| `03_data_quality_check.sql` | Full check suite — run before modelling |
| `04_dedupe_raw.sql` | Removes the duplicate rows the checks identify |
| `05_build_dwh.sql` | Builds dimensions and fact tables |
| `06_build_mart.sql` | Builds the report views and the eCPM price table |
| `07_build_retention_curve.sql` | Cohort retention curve, by install week and day-N |
| `08_build_retention_summary.sql` | Flat D1 / D7 / D30 retention figures |
| `09_build_retention_by_dimension.sql` | The same retention figures, cut by country, tier, source and cohort week |

Each script ends with verification queries. Run them — several check invariants that would otherwise fail silently.

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

---

## Measuring retention

Retention is cohort-based: each user is evaluated against **their own** install date, and only once enough days have passed for that measurement to be possible.

This second condition matters. A user who installed on 30 July cannot have a day-7 data point when the data ends on 31 July — counting them in the denominator understates retention, and the distortion grows with N. Every retention measure here, in SQL and in DAX, excludes users whose install date is less than N days before the last tracked date.

Aggregation across cohorts is weighted — `SUM(active) / SUM(cohort)`, never an average of per-cohort ratios. Cohort sizes vary by more than an order of magnitude, so an unweighted average gives a materially different and incorrect answer.

`powerbi/dax_measures.md` documents the measures that implement this.

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
