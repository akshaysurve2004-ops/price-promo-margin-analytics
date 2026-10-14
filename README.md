Price-Promo-Margin Analytics (SQL)
A MySQL star-schema project that analyses pricing, promotions and margin for a food-delivery business, with data-quality checks and reconciled KPI reporting.
Business Questions
Which categories, meals and fulfilment centers drive revenue?
How do promotion channels (email, homepage, both) compare with no promotion?
How does discount depth relate to order volume?
What is gross margin by category, promo type, and center type and region?
How is revenue trending week over week?
Data Model
Star schema with one fact table and four dimension tables:
Table
Role
fact_orders
One row per center-meal-week order record (price, discount, promo flags, units, revenue)
dim_meal
Meal category and cuisine
dim_center
City, region, center type and operating area
dim_week
Week number with a repeating 52-week cycle for period and quarter rollups
dim_cogs_assumptions
Assumed cost-of-goods % by category (kept separate so real cost data can replace it)
<!-- If you add an ERD image to the docs folder, remove the arrows on the next line -->
<!--  -->
Repository Contents
File
Purpose
sql/01_schema_and_seed_data.sql
Tables, constraints, indexes, demo data, validation checks
sql/02_analysis_queries.sql
22 numbered queries: KPIs, promotion, discount, margin, ranking and reconciliation
Techniques Used
CTEs and subqueries
Window functions: LAG, RANK, DENSE_RANK
Conditional aggregation with CASE
Divide-by-zero safeguards with NULLIF
Data-quality checks: nulls, duplicates, ranges, orphan keys and recalculation of price and revenue
Reconciliation of totals across category, promo and margin outputs
Data-Quality Approach
Every KPI is preceded by validation checks, and each check should return zero rows:
Null and duplicate checks on keys
Range checks on prices, discounts and flags
Referential-integrity checks against all three dimensions
Recalculation of discount_amount and revenue from their inputs
Reconciliation of total revenue and gross profit across reports
Key Findings
Replace these with your real results after running the scripts.
[Top category and its share of total revenue]
[Best-performing promotion type compared with non-promoted records]
[Margin difference between categories or promo types]
[Strongest and weakest center type or region]
Assumptions and Limitations
COGS is an assumed percentage by category, so margin figures are illustrative until real cost data replaces them.
The demo data in the seed script is synthetic. Load your real CSVs using the instructions in the schema file to analyse real data.
Discount-versus-volume analysis shows a directional relationship only. Discounts overlap with promotions, so it is not a proven price elasticity.
Promotion comparisons show association with non-promoted records, not proven incremental lift.
Price-volume decomposition at category level leaves an interaction term, not true mix.
How to Run
Install MySQL 8.0 or later.
Run sql/01_schema_and_seed_data.sql to create the database, tables and demo data.
Run the queries in sql/02_analysis_queries.sql one at a time and compare the totals in the reconciliation section.
Next Steps
Build a Power BI dashboard on top of the star schema
Add real calendar dates to dim_week
Replace assumed COGS with real cost data
Meal-level price-volume-mix analysis
A regression-based price elasticity estimate controlling for promotion type
Author
Akshay Surve | IE MBA in Business Analytics |  Data Analyst
www.linkedin.com/in/akshay-surve-5477562ba| akshaysurve2004@gmail.com
