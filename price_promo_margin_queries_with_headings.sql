-- ============================================================================
-- PRICE-PROMO-MARGIN ANALYTICS: FOOD DELIVERY CASE STUDY
-- Analysis and Reconciliation Queries (MySQL 8.0+)
--
-- Star schema: fact_orders + dim_meal, dim_center, dim_week, dim_cogs_assumptions
-- Note: margin figures use ASSUMED COGS % by category (dim_cogs_assumptions),
--       so margin is illustrative until real cost data replaces it.
--
-- CONTENTS
--   A. Headline and Contribution KPIs ........ Queries 1-4
--   B. Promotion Analysis .................... Queries 5-7
--   C. Discount Analysis ..................... Queries 8-9
--   D. Margin Analysis ....................... Queries 10-12
--   E. Trend, Ranking and Benchmarking ....... Queries 13-16
--   F. Reconciliation and Integrity Checks ... Queries 17-22
-- ============================================================================

USE price_promo_margin;


-- ############################################################################
-- A. HEADLINE AND CONTRIBUTION KPIs
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 1: Headline KPI Summary
-- Business question: How big is the business at a glance?
-- Output: one row with record count, total units, total revenue, average
--         checkout price, average base price and average discount %.
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*)                                  AS total_records,
    SUM(num_orders)                           AS total_orders_or_units,
    ROUND(SUM(revenue), 2)                    AS total_revenue,
    ROUND(AVG(checkout_price), 2)             AS average_checkout_price,
    ROUND(AVG(base_price), 2)                 AS average_base_price,
    ROUND(AVG(discount_pct) * 100, 2)         AS average_discount_percentage
FROM fact_orders;


-- ----------------------------------------------------------------------------
-- Query 2: Revenue Contribution by Category
-- Business question: Which categories drive the business?
-- Output: units, revenue and % share of total revenue per category.
-- ----------------------------------------------------------------------------
SELECT
    m.category,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue,
    ROUND(
        100.0 * SUM(f.revenue)
        / NULLIF((SELECT SUM(revenue) FROM fact_orders), 0),
        2
    )                                         AS revenue_contribution_pct
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
GROUP BY m.category
ORDER BY total_revenue DESC;


-- ----------------------------------------------------------------------------
-- Query 3: Meal-Level Performance
-- Business question: Which individual meals sell the most and at what
--                    realised price per unit?
-- Output: units, revenue and revenue per unit for every meal.
-- ----------------------------------------------------------------------------
SELECT
    m.meal_id,
    m.category,
    m.cuisine,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue,
    ROUND(SUM(f.revenue) / NULLIF(SUM(f.num_orders), 0), 2)
                                              AS revenue_per_order_or_unit
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
GROUP BY m.meal_id, m.category, m.cuisine
ORDER BY total_revenue DESC;


-- ----------------------------------------------------------------------------
-- Query 4: Fulfilment Center Performance
-- Business question: Which centers generate the most volume and revenue?
-- Output: units and revenue per center, with type, region, city and area.
-- ----------------------------------------------------------------------------
SELECT
    dc.center_id,
    dc.center_type,
    dc.region_code,
    dc.city_code,
    dc.op_area,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue
FROM fact_orders f
JOIN dim_center dc
    ON f.center_id = dc.center_id
GROUP BY dc.center_id, dc.center_type, dc.region_code, dc.city_code, dc.op_area
ORDER BY total_revenue DESC;


-- ############################################################################
-- B. PROMOTION ANALYSIS
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 5: Performance by Promotion Channel
-- Business question: How do None, Email Only, Homepage Only and Both compare?
-- Output: records, units, average units per record, revenue, average price
--         and average discount for each promo type.
-- Note: compares averages (association), not proven incremental lift.
-- ----------------------------------------------------------------------------
SELECT
    f.promo_type,
    COUNT(*)                                  AS order_records,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(AVG(f.num_orders), 2)               AS average_orders_or_units_per_record,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue,
    ROUND(AVG(f.checkout_price), 2)           AS average_checkout_price,
    ROUND(AVG(f.discount_pct) * 100, 2)       AS average_discount_pct
FROM fact_orders f
GROUP BY f.promo_type
ORDER BY total_revenue DESC;


-- ----------------------------------------------------------------------------
-- Query 6: Promotional vs Non-Promotional Records
-- Business question: Do promoted records sell more than non-promoted ones?
-- Output: two-row comparison (Promotional = emailed OR homepage featured).
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN emailer_for_promotion = 1
          OR homepage_featured = 1
        THEN 'Promotional'
        ELSE 'Non-Promotional'
    END                                       AS promotion_status,
    COUNT(*)                                  AS order_records,
    SUM(num_orders)                           AS total_orders_or_units,
    ROUND(SUM(revenue), 2)                    AS total_revenue,
    ROUND(AVG(num_orders), 2)                 AS average_orders_or_units_per_record,
    ROUND(AVG(checkout_price), 2)             AS average_checkout_price
FROM fact_orders
GROUP BY promotion_status
ORDER BY total_revenue DESC;


-- ----------------------------------------------------------------------------
-- Query 7: Promotion Channel Performance within Each Category
-- Business question: Which promotion channel works best for each category?
-- Output: records, units, revenue and revenue per unit by category and promo.
-- ----------------------------------------------------------------------------
SELECT
    m.category,
    f.promo_type,
    COUNT(*)                                  AS order_records,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue,
    ROUND(SUM(f.revenue) / NULLIF(SUM(f.num_orders), 0), 2)
                                              AS revenue_per_order_or_unit
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
GROUP BY m.category, f.promo_type
ORDER BY m.category, total_revenue DESC;


-- ############################################################################
-- C. DISCOUNT ANALYSIS
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 8: Discount Band Analysis (Overall)
-- Business question: Does deeper discounting go with higher volume?
-- Output: records, units, revenue and price by discount band.
-- Note: directional relationship only; discounts overlap with promotions.
-- ----------------------------------------------------------------------------
SELECT
    CASE
        WHEN discount_pct <= 0    THEN '0. No Discount'
        WHEN discount_pct <= 0.10 THEN '1. Up to 10%'
        WHEN discount_pct <= 0.20 THEN '2. 10-20%'
        WHEN discount_pct <= 0.30 THEN '3. 20-30%'
        ELSE '4. Above 30%'
    END                                       AS discount_band,
    COUNT(*)                                  AS order_records,
    SUM(num_orders)                           AS total_orders_or_units,
    ROUND(AVG(num_orders), 2)                 AS average_orders_or_units_per_record,
    ROUND(SUM(revenue), 2)                    AS total_revenue,
    ROUND(AVG(checkout_price), 2)             AS average_checkout_price
FROM fact_orders
GROUP BY discount_band
ORDER BY discount_band;


-- ----------------------------------------------------------------------------
-- Query 9: Discount Band Analysis by Category (Price Sensitivity Proxy)
-- Business question: Which categories respond most to discounting?
-- Output: records, units, revenue and average discount by category and band.
-- ----------------------------------------------------------------------------
SELECT
    m.category,
    CASE
        WHEN f.discount_pct <= 0    THEN 'No Discount'
        WHEN f.discount_pct <= 0.10 THEN 'Up to 10%'
        WHEN f.discount_pct <= 0.20 THEN '10-20%'
        WHEN f.discount_pct <= 0.30 THEN '20-30%'
        ELSE 'Above 30%'
    END                                       AS discount_band,
    COUNT(*)                                  AS order_records,
    SUM(f.num_orders)                         AS total_orders_or_units,
    ROUND(SUM(f.revenue), 2)                  AS total_revenue,
    ROUND(AVG(f.discount_pct) * 100, 2)       AS average_discount_pct
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
GROUP BY m.category, discount_band
ORDER BY m.category, discount_band;


-- ############################################################################
-- D. MARGIN ANALYSIS (assumed COGS)
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 10: Gross Margin by Category
-- Business question: Which categories earn the most profit and at what margin?
-- Output: revenue, estimated COGS, estimated gross profit and margin %.
-- ----------------------------------------------------------------------------
SELECT
    m.category,
    ROUND(SUM(f.revenue), 2)                                AS total_revenue,
    ROUND(SUM(f.revenue * c.assumed_cogs_pct), 2)           AS estimated_cogs,
    ROUND(SUM(f.revenue * (1 - c.assumed_cogs_pct)), 2)     AS estimated_gross_profit,
    ROUND(
        100.0 * (
            SUM(f.revenue * (1 - c.assumed_cogs_pct))
            / NULLIF(SUM(f.revenue), 0)
        ),
        2
    )                                                       AS estimated_gross_margin_pct
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
JOIN dim_cogs_assumptions c
    ON m.category = c.category
GROUP BY m.category
ORDER BY estimated_gross_profit DESC;


-- ----------------------------------------------------------------------------
-- Query 11: Gross Margin by Promotion Channel
-- Business question: Do promotions grow revenue at the cost of margin?
-- Output: revenue, estimated COGS, gross profit and margin % per promo type.
-- ----------------------------------------------------------------------------
SELECT
    f.promo_type,
    ROUND(SUM(f.revenue), 2)                                AS total_revenue,
    ROUND(SUM(f.revenue * c.assumed_cogs_pct), 2)           AS estimated_cogs,
    ROUND(SUM(f.revenue * (1 - c.assumed_cogs_pct)), 2)     AS estimated_gross_profit,
    ROUND(
        100.0 * SUM(f.revenue * (1 - c.assumed_cogs_pct))
        / NULLIF(SUM(f.revenue), 0),
        2
    )                                                       AS estimated_gross_margin_pct
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
JOIN dim_cogs_assumptions c
    ON m.category = c.category
GROUP BY f.promo_type
ORDER BY estimated_gross_profit DESC;


-- ----------------------------------------------------------------------------
-- Query 12: Profitability by Center Type and Region
-- Business question: Which center types and regions are most profitable?
-- Output: center count, revenue, gross profit and margin % by type and region.
-- ----------------------------------------------------------------------------
SELECT
    dc.center_type,
    dc.region_code,
    COUNT(DISTINCT dc.center_id)                            AS total_centres,
    ROUND(SUM(f.revenue), 2)                                AS total_revenue,
    ROUND(SUM(f.revenue * (1 - c.assumed_cogs_pct)), 2)     AS estimated_gross_profit,
    ROUND(
        100.0 * SUM(f.revenue * (1 - c.assumed_cogs_pct))
        / NULLIF(SUM(f.revenue), 0),
        2
    )                                                       AS estimated_gross_margin_pct
FROM fact_orders f
JOIN dim_center dc
    ON f.center_id = dc.center_id
JOIN dim_meal m
    ON f.meal_id = m.meal_id
JOIN dim_cogs_assumptions c
    ON m.category = c.category
GROUP BY dc.center_type, dc.region_code
ORDER BY estimated_gross_profit DESC;


-- ############################################################################
-- E. TREND, RANKING AND BENCHMARKING
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 13: Week-over-Week Revenue Growth
-- Business question: How is revenue trending week to week?
-- Technique: CTE + LAG() window function; NULLIF guards against divide-by-zero.
-- ----------------------------------------------------------------------------
WITH weekly_revenue AS (
    SELECT
        week_number,
        SUM(revenue) AS total_revenue
    FROM fact_orders
    GROUP BY week_number
),
revenue_comparison AS (
    SELECT
        week_number,
        total_revenue,
        LAG(total_revenue) OVER (ORDER BY week_number) AS previous_week_revenue
    FROM weekly_revenue
)
SELECT
    week_number,
    ROUND(total_revenue, 2)                   AS current_week_revenue,
    ROUND(previous_week_revenue, 2)           AS previous_week_revenue,
    ROUND(total_revenue - previous_week_revenue, 2) AS revenue_change,
    ROUND(
        100.0 * (total_revenue - previous_week_revenue)
        / NULLIF(previous_week_revenue, 0),
        2
    )                                         AS revenue_growth_pct
FROM revenue_comparison
ORDER BY week_number;


-- ----------------------------------------------------------------------------
-- Query 14: Category Revenue Ranking
-- Business question: What is the rank order of categories by revenue?
-- Technique: RANK() window function over an aggregated CTE.
-- ----------------------------------------------------------------------------
WITH category_revenue AS (
    SELECT
        m.category,
        SUM(f.revenue) AS total_revenue
    FROM fact_orders f
    JOIN dim_meal m
        ON f.meal_id = m.meal_id
    GROUP BY m.category
)
SELECT
    category,
    ROUND(total_revenue, 2)                   AS total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM category_revenue
ORDER BY revenue_rank;


-- ----------------------------------------------------------------------------
-- Query 15: Center Ranking within Each Center Type
-- Business question: Who are the top and bottom centers within their type?
-- Technique: DENSE_RANK() with PARTITION BY center_type.
-- ----------------------------------------------------------------------------
WITH center_revenue AS (
    SELECT
        dc.center_id,
        dc.center_type,
        dc.region_code,
        SUM(f.revenue) AS total_revenue
    FROM fact_orders f
    JOIN dim_center dc
        ON f.center_id = dc.center_id
    GROUP BY dc.center_id, dc.center_type, dc.region_code
)
SELECT
    center_id,
    center_type,
    region_code,
    ROUND(total_revenue, 2)                   AS total_revenue,
    DENSE_RANK() OVER (
        PARTITION BY center_type
        ORDER BY total_revenue DESC
    )                                         AS centre_rank
FROM center_revenue
ORDER BY center_type, centre_rank;


-- ----------------------------------------------------------------------------
-- Query 16: Categories with Below-Average Margin
-- Business question: Which categories dilute overall profitability?
-- Technique: CTE + scalar subquery benchmark.
-- Note: the benchmark is a simple average of category margin %. A
--       revenue-weighted average (total gross profit / total revenue) is the
--       stricter alternative.
-- ----------------------------------------------------------------------------
WITH category_metrics AS (
    SELECT
        m.category,
        SUM(f.revenue)                                      AS total_revenue,
        SUM(f.revenue * (1 - c.assumed_cogs_pct))           AS estimated_gross_profit,
        100.0 * SUM(f.revenue * (1 - c.assumed_cogs_pct))
            / NULLIF(SUM(f.revenue), 0)                     AS estimated_gross_margin_pct
    FROM fact_orders f
    JOIN dim_meal m
        ON f.meal_id = m.meal_id
    JOIN dim_cogs_assumptions c
        ON m.category = c.category
    GROUP BY m.category
)
SELECT
    category,
    ROUND(total_revenue, 2)                   AS total_revenue,
    ROUND(estimated_gross_profit, 2)          AS estimated_gross_profit,
    ROUND(estimated_gross_margin_pct, 2)      AS estimated_gross_margin_pct
FROM category_metrics
WHERE estimated_gross_margin_pct < (
    SELECT AVG(estimated_gross_margin_pct)
    FROM category_metrics
)
ORDER BY total_revenue DESC;


-- ############################################################################
-- F. RECONCILIATION AND INTEGRITY CHECKS
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Query 17: COGS Assumption Coverage Check
-- Purpose: every meal category must have a COGS assumption, otherwise the
--          margin queries silently drop revenue. Expected result: 0 rows.
-- ----------------------------------------------------------------------------
SELECT DISTINCT
    m.category
FROM dim_meal m
LEFT JOIN dim_cogs_assumptions c
    ON m.category = c.category
WHERE c.category IS NULL;


-- ----------------------------------------------------------------------------
-- Query 18: Week Dimension Coverage Check
-- Purpose: confirm the first week, last week and number of weeks loaded.
-- ----------------------------------------------------------------------------
SELECT
    MIN(week_number) AS first_week,
    MAX(week_number) AS last_week,
    COUNT(*)         AS weeks_in_dimension
FROM dim_week;


-- ----------------------------------------------------------------------------
-- Query 19: Reconciliation 1 of 3 - Total Revenue in the Fact Table
-- Purpose: the control total every other report must tie back to.
-- ----------------------------------------------------------------------------
SELECT
    ROUND(SUM(revenue), 2) AS total_fact_revenue
FROM fact_orders;


-- ----------------------------------------------------------------------------
-- Query 20: Reconciliation 2 of 3 - Sum of Category Revenue
-- Purpose: must equal Query 19. A mismatch means a join dropped or
--          duplicated rows.
-- ----------------------------------------------------------------------------
SELECT
    ROUND(SUM(category_revenue), 2) AS total_category_revenue
FROM (
    SELECT
        m.category,
        SUM(f.revenue) AS category_revenue
    FROM fact_orders f
    JOIN dim_meal m
        ON f.meal_id = m.meal_id
    GROUP BY m.category
) AS category_totals;


-- ----------------------------------------------------------------------------
-- Query 21: Reconciliation 3 of 3 - Total Estimated Gross Profit
-- Purpose: must equal the sum of gross profit across Queries 10, 11 and 12.
-- ----------------------------------------------------------------------------
SELECT
    ROUND(SUM(f.revenue * (1 - c.assumed_cogs_pct)), 2) AS total_estimated_gross_profit
FROM fact_orders f
JOIN dim_meal m
    ON f.meal_id = m.meal_id
JOIN dim_cogs_assumptions c
    ON m.category = c.category;


-- ----------------------------------------------------------------------------
-- Query 22: Row Count Check Across All Tables
-- Purpose: confirm every table loaded and report the record count of each.
-- ----------------------------------------------------------------------------
SELECT 'fact_orders' AS table_name, COUNT(*) AS total_rows FROM fact_orders
UNION ALL
SELECT 'dim_meal', COUNT(*) FROM dim_meal
UNION ALL
SELECT 'dim_center', COUNT(*) FROM dim_center
UNION ALL
SELECT 'dim_week', COUNT(*) FROM dim_week
UNION ALL
SELECT 'dim_cogs_assumptions', COUNT(*) FROM dim_cogs_assumptions;
