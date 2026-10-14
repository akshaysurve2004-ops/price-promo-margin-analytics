-- ============================================================================
-- Price-Promo-Margin Analytics: A Food Delivery Case Study
-- Star schema DDL, load statements, and core RGM analytical queries
-- Target: PostgreSQL (adjust COPY syntax for Snowflake/other engines as noted)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_meal;
DROP TABLE IF EXISTS dim_center;
DROP TABLE IF EXISTS dim_week;
DROP TABLE IF EXISTS dim_cogs_assumptions;

-- Dimension: meal
CREATE TABLE dim_meal (
    meal_id     INTEGER PRIMARY KEY,
    category    VARCHAR(30) NOT NULL,
    cuisine     VARCHAR(20) NOT NULL
);

-- Dimension: fulfilment center
CREATE TABLE dim_center (
    center_id    INTEGER PRIMARY KEY,
    city_code    INTEGER NOT NULL,
    region_code  INTEGER NOT NULL,
    center_type  VARCHAR(10) NOT NULL,
    op_area      NUMERIC(4,1) NOT NULL
);

-- Dimension: week (no real calendar dates in source data, so this models
-- weeks 1-145 as a 52-week repeating cycle for period/quarter rollups)
CREATE TABLE dim_week (
    week_number       INTEGER PRIMARY KEY,
    cycle_year         INTEGER NOT NULL,
    period_in_cycle     INTEGER NOT NULL,
    quarter_in_cycle    INTEGER NOT NULL
);

-- Assumptions table: assumed cost-of-goods % by category (no cost data in
-- the raw dataset — this is the analyst judgment layer, documented in the
-- Excel COGS_Assumptions sheet). Kept as its own table so it's easy to swap
-- in real cost data later without touching the fact table.
CREATE TABLE dim_cogs_assumptions (
    category           VARCHAR(30) PRIMARY KEY,
    assumed_cogs_pct   NUMERIC(4,3) NOT NULL
);

-- Fact: one row per center-meal-week order record
CREATE TABLE fact_orders (
    order_id                BIGINT PRIMARY KEY,
    week_number             INTEGER NOT NULL REFERENCES dim_week(week_number),
    center_id               INTEGER NOT NULL REFERENCES dim_center(center_id),
    meal_id                 INTEGER NOT NULL REFERENCES dim_meal(meal_id),
    checkout_price           NUMERIC(8,2) NOT NULL,
    base_price               NUMERIC(8,2) NOT NULL,
    discount_amount          NUMERIC(8,2) NOT NULL,
    discount_pct             NUMERIC(6,4) NOT NULL,
    emailer_for_promotion     SMALLINT NOT NULL,
    homepage_featured         SMALLINT NOT NULL,
    promo_type               VARCHAR(15) NOT NULL,   -- None / Email Only / Homepage Only / Both
    num_orders                INTEGER NOT NULL,
    revenue                  NUMERIC(12,2) NOT NULL
);

CREATE INDEX idx_fact_orders_meal   ON fact_orders(meal_id);
CREATE INDEX idx_fact_orders_center ON fact_orders(center_id);
CREATE INDEX idx_fact_orders_week   ON fact_orders(week_number);
CREATE INDEX idx_fact_orders_promo  ON fact_orders(promo_type);

-- ----------------------------------------------------------------------------
-- 2. LOAD
-- ----------------------------------------------------------------------------
-- Files referenced below (exported alongside this script):
--   dim_meal.csv, dim_center.csv, dim_week.csv, dim_cogs_assumptions.csv, fact_orders.csv
--
-- PostgreSQL (psql, run from the machine holding the CSVs):
--   \copy dim_meal             FROM 'dim_meal.csv'             DELIMITER ',' CSV HEADER;
--   \copy dim_center           FROM 'dim_center.csv'           DELIMITER ',' CSV HEADER;
--   \copy dim_week             FROM 'dim_week.csv'             DELIMITER ',' CSV HEADER;
--   \copy dim_cogs_assumptions FROM 'dim_cogs_assumptions.csv' DELIMITER ',' CSV HEADER;
--   \copy fact_orders          FROM 'fact_orders.csv'          DELIMITER ',' CSV HEADER;
--
-- Load dimensions BEFORE the fact table — fact_orders has foreign keys into
-- dim_meal, dim_center, and dim_week, so those three must exist first.
--
-- Snowflake equivalent (after PUT-ing files to a stage):
--   COPY INTO dim_meal   FROM @my_stage/dim_meal.csv   FILE_FORMAT = (TYPE=CSV SKIP_HEADER=1);
--   -- (repeat per table, same load order)
--
-- Fivetran: point a File/CSV connector at these files (or their upstream
-- source) and map to the same table/column names — Fivetran will keep the
-- fact table refreshed on schedule once this is your ongoing pipeline
-- instead of a one-time load.

-- ----------------------------------------------------------------------------
-- 3. CORE RGM ANALYTICAL QUERIES
-- ----------------------------------------------------------------------------

-- 3a. Promo ROI: incremental orders and revenue by promo channel combination,
--     per category. Compares None / Email Only / Homepage Only / Both.
SELECT
    m.category,
    f.promo_type,
    COUNT(*)                                   AS order_records,
    SUM(f.num_orders)                          AS total_units,
    ROUND(AVG(f.num_orders), 1)                AS avg_units_per_record,
    SUM(f.revenue)                             AS total_revenue,
    ROUND(SUM(f.revenue) / NULLIF(SUM(f.num_orders), 0), 2) AS revenue_per_unit
FROM fact_orders f
JOIN dim_meal m ON m.meal_id = f.meal_id
GROUP BY m.category, f.promo_type
ORDER BY m.category,
    CASE f.promo_type
        WHEN 'None' THEN 0 WHEN 'Email Only' THEN 1
        WHEN 'Homepage Only' THEN 2 WHEN 'Both' THEN 3 END;

-- 3b. Price elasticity proxy: correlation direction between discount depth
--     and order volume, by category. A steeper negative-to-positive slope on
--     avg_units across discount bands signals higher elasticity.
SELECT
    m.category,
    CASE
        WHEN f.discount_pct <= 0        THEN '0. No discount / markup'
        WHEN f.discount_pct <= 0.10     THEN '1. 0-10%'
        WHEN f.discount_pct <= 0.20     THEN '2. 10-20%'
        WHEN f.discount_pct <= 0.30     THEN '3. 20-30%'
        ELSE '4. 30%+'
    END AS discount_band,
    COUNT(*)                       AS order_records,
    ROUND(AVG(f.num_orders), 1)     AS avg_units_per_record,
    SUM(f.revenue)                 AS total_revenue
FROM fact_orders f
JOIN dim_meal m ON m.meal_id = f.meal_id
GROUP BY m.category, discount_band
ORDER BY m.category, discount_band;

-- 3c. Margin bridge: revenue, assumed COGS, and gross margin by category —
--     the pocket-margin view built from the assumptions table.
SELECT
    m.category,
    SUM(f.revenue)                                              AS total_revenue,
    SUM(f.revenue) * MAX(c.assumed_cogs_pct)                    AS total_cogs,
    SUM(f.revenue) * (1 - MAX(c.assumed_cogs_pct))              AS total_gross_margin,
    ROUND(1 - MAX(c.assumed_cogs_pct), 4)                       AS margin_pct
FROM fact_orders f
JOIN dim_meal m ON m.meal_id = f.meal_id
JOIN dim_cogs_assumptions c ON c.category = m.category
GROUP BY m.category
ORDER BY total_gross_margin DESC;

-- 3d. Channel/center profitability: revenue and margin by center_type and region.
SELECT
    dc.center_type,
    dc.region_code,
    SUM(f.revenue)                                               AS total_revenue,
    SUM(f.revenue * (1 - ca.assumed_cogs_pct))                    AS total_gross_margin,
    COUNT(DISTINCT f.center_id)                                   AS center_count
FROM fact_orders f
JOIN dim_center dc ON dc.center_id = f.center_id
JOIN dim_meal m ON m.meal_id = f.meal_id
JOIN dim_cogs_assumptions ca ON ca.category = m.category
GROUP BY dc.center_type, dc.region_code
ORDER BY total_gross_margin DESC;

-- 3e. Week-over-week price-volume-mix decomposition (simplified):
--     revenue change vs. prior week, split into a price-effect and a
--     volume-effect component at the category level. Mix effect falls out
--     as the residual between total revenue change and the sum of the two.
WITH weekly_category AS (
    SELECT
        m.category,
        f.week_number,
        SUM(f.num_orders)                                    AS units,
        SUM(f.revenue)                                       AS revenue,
        SUM(f.revenue) / NULLIF(SUM(f.num_orders), 0)         AS avg_price
    FROM fact_orders f
    JOIN dim_meal m ON m.meal_id = f.meal_id
    GROUP BY m.category, f.week_number
),
with_prior AS (
    SELECT
        *,
        LAG(units) OVER (PARTITION BY category ORDER BY week_number)     AS prior_units,
        LAG(avg_price) OVER (PARTITION BY category ORDER BY week_number) AS prior_avg_price,
        LAG(revenue) OVER (PARTITION BY category ORDER BY week_number)   AS prior_revenue
    FROM weekly_category
)
SELECT
    category,
    week_number,
    revenue - prior_revenue                                     AS revenue_change,
    (avg_price - prior_avg_price) * prior_units                 AS price_effect,
    (units - prior_units) * prior_avg_price                     AS volume_effect,
    (revenue - prior_revenue)
        - ((avg_price - prior_avg_price) * prior_units)
        - ((units - prior_units) * prior_avg_price)              AS mix_residual
FROM with_prior
WHERE prior_units IS NOT NULL
ORDER BY category, week_number;
