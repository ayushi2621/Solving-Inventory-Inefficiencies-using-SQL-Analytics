---------------------------
-- Schema design --
---------------------------
CREATE SCHEMA inventory_sql_project;
USE inventory_sql_project;

-- full data
CREATE TABLE sales_data (
    date DATE,
    store_id VARCHAR(10),
    product_id VARCHAR(10),
    category VARCHAR(50),
    region VARCHAR(50),
    inventory_level INT,
    units_sold INT,
    units_ordered INT,
    demand_forecast FLOAT,
    price FLOAT,
    discount INT,
    weather_condition VARCHAR(50),
    holiday_promotion BOOLEAN,
    competitor_pricing FLOAT,
    seasonality VARCHAR(20)
);

-- Products table
CREATE TABLE products (
    product_id VARCHAR(10) PRIMARY KEY,
    category VARCHAR(50)
);
INSERT INTO products
SELECT DISTINCT product_id, category
FROM sales_data;


-- Stores table
CREATE TABLE stores (
    store_id VARCHAR(10) PRIMARY KEY
);
INSERT INTO stores
SELECT DISTINCT store_id
FROM sales_data;


-- Dates table
CREATE TABLE dates (
    date DATE PRIMARY KEY,
    day INT,
    month INT,
    year INT
);
INSERT INTO dates (date, day, month, year)
SELECT DISTINCT
    date,
    DAY(date),
    MONTH(date),
    YEAR(date)
FROM sales_data;


-- seasons (waise jrurat nahi if proper normalise kr rhe badme hata denge agar hatana ho to)
CREATE TABLE seasons (
    month INT PRIMARY KEY,
    season VARCHAR(20)
);
INSERT INTO seasons (month, season)
VALUES 
    (1, 'Winter'),
    (2, 'Winter'),
    (3, 'Spring'),
    (4, 'Spring'),
    (5, 'Summer'),
    (6, 'Summer'),
    (7, 'Summer'),
    (8, 'Summer'),
    (9, 'Autumn'),
    (10, 'Autumn'),
    (11, 'Winter'),
    (12, 'Winter');


-- sales facts table
CREATE TABLE sales (
    date DATE,
    store_id VARCHAR(10),
    product_id VARCHAR(10),

    region VARCHAR(50),
    inventory_level INT,
    units_sold INT,
    units_ordered INT,
    demand_forecast FLOAT,
    price FLOAT,
    discount INT,
    competitor_pricing FLOAT,

    weather_condition VARCHAR(50),
    holiday_promotion BOOLEAN,

    PRIMARY KEY (date, store_id, product_id),
    FOREIGN KEY (date) REFERENCES dates(date),
    FOREIGN KEY (store_id) REFERENCES stores(store_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);
INSERT INTO sales (
    date, store_id, product_id, region,
    inventory_level, units_sold, units_ordered,
    demand_forecast, price, discount, competitor_pricing,
    weather_condition, holiday_promotion)
SELECT
    date, store_id, product_id, region,
    inventory_level, units_sold, units_ordered,
    demand_forecast, price, discount, competitor_pricing,
    weather_condition, holiday_promotion
FROM sales_data;


-- Feature creation
ALTER TABLE sales
ADD inventory_lvl_at_eod INT,
ADD revenue FLOAT,
ADD deviation_from_forecast FLOAT,
ADD diffr_from_comp_price FLOAT;

SET SQL_SAFE_UPDATES = 0;

UPDATE sales
SET inventory_lvl_at_eod = inventory_level - units_sold;
UPDATE sales
SET revenue = (price - discount)*units_sold;
UPDATE sales
SET deviation_from_forecast = units_sold - demand_forecast;
UPDATE sales
SET diffr_from_comp_price = competitor_pricing - price;

SET SQL_SAFE_UPDATES = 1;

ALTER TABLE sales DROP COLUMN deviation_from_forecast;
ALTER TABLE sales ADD COLUMN deviation_from_forecast FLOAT;
UPDATE sales
SET deviation_from_forecast = units_sold - demand_forecast;

-- i saw i negative value in the revenue, lets see is it only case or there is some serious issue
SELECT store_id, product_id, discount, price, revenue FROM sales WHERE revenue<0;
-- 1847 rows are having -ve revenue so i think the discount isnt the discount value its percent lets change
ALTER TABLE sales DROP COLUMN revenue;
ALTER TABLE sales ADD COLUMN revenue FLOAT;
UPDATE sales 
SET revenue = price * (1 - discount / 100)*units_sold;

SELECT product_id, COUNT(*) AS understock_events
FROM sales
WHERE inventory_level < units_sold
GROUP BY product_id
ORDER BY understock_events DESC;


-- ==================== --
-- Product lvl analysis --
-- ==================== --
SELECT category, COUNT(product_id) 
FROM products 
GROUP BY category;
-- we have uneven distribution of products 11-clothing, 8-electronics, 6 furniture, 2 groceries 3 toys

SELECT product_id, SUM(revenue) as prod_rev 
FROM sales 
GROUP BY product_id 
ORDER BY prod_rev DESC;

SELECT 
    product_id, 
    ROUND(SUM(revenue),2) AS prod_rev,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (), 2) AS percent_of_total_revenue
FROM sales
GROUP BY product_id
ORDER BY percent_of_total_revenue DESC;
-- Product revenue ranges from 3.69% to 2.99%. P0066,P0061 & P0133 are the top ones while P0159 P0068 and P0070 are bottom 3.

-- category wise revenue
SELECT 
    p.category,
    ROUND(SUM(s.revenue),2) AS cat_rev,
    ROUND(SUM(s.revenue) * 100.0 / SUM(SUM(s.revenue)) OVER (), 2) AS percent_of_total_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY percent_of_total_revenue DESC;
-- Since clothing and electronics are the major vairety being sold they contribute to max revenue (39.9+24.31) 
-- THis doesnt give clear idea, lets see normlasied %rev of category per product


SELECT 
    p.category,
    COUNT(DISTINCT p.product_id) AS num_products,
    ROUND(SUM(s.revenue), 2) AS cat_rev,
    ROUND(SUM(s.revenue) / COUNT(DISTINCT p.product_id), 2) AS avg_rev_per_product,
    ROUND(
        (SUM(s.revenue) / COUNT(DISTINCT p.product_id)) * 100.0 / 
        SUM(SUM(s.revenue) / COUNT(DISTINCT p.product_id)) OVER (), 
        2
    ) AS normalized_percent_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY normalized_percent_revenue DESC;
-- Clothing still remain at top, electronics being the lower one with 18.38% normalised percent revenue, less than more than 3 % from clothing


-- regional
SELECT 
    region,
    ROUND(SUM(revenue),2) AS reg_rev,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (), 2) AS percent_of_total_revenue
FROM sales
GROUP BY region
ORDER BY percent_of_total_revenue DESC;
-- Almost similar revenue, with only east above 25% which is 25.21, rest W-24.98, N-24,93, S-24.88


SELECT 
    region,
    product_id,
    SUM(revenue) AS total_revenue,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (PARTITION BY region), 2) AS percent_of_region_revenue
FROM sales
GROUP BY region, product_id
ORDER BY region, percent_of_region_revenue DESC; 
-- Top products generaly have 3.75-3.85% contribution while lower ones <=3% contribution per region
-- Top ones -> East P0066,61, North 61,66,69, South -46,133, West - 178,57

SELECT 
    s.region, p.category, ROUND(SUM(s.revenue),2) AS total_revenue,
    ROUND(SUM(s.revenue) * 100.0 / SUM(SUM(s.revenue)) OVER (PARTITION BY s.region), 2) AS percent_of_region_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY s.region, p.category
ORDER BY s.region, percent_of_region_revenue DESC;
-- clothing aprox 40% rev, electronics with 24.6, furniture 19, toys 9.5, groceries 6.9

WITH category_revenue AS (
    SELECT 
        s.region,
        p.category,
        COUNT(DISTINCT p.product_id) AS product_count,
        SUM(s.revenue) AS total_revenue
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    GROUP BY s.region, p.category),
normalized AS (
    SELECT
        region, category, product_count, total_revenue,
        total_revenue * 1.0 / product_count AS avg_revenue_per_product
    FROM category_revenue),
region_totals AS (
    SELECT 
        region,
        SUM(avg_revenue_per_product) AS region_total_avg_revenue
    FROM normalized
    GROUP BY region)
SELECT 
    n.region,
    n.category,
    ROUND(n.total_revenue, 2) AS total_revenue,
    n.product_count,
    ROUND(n.avg_revenue_per_product, 2) AS avg_revenue_per_product,
    ROUND(n.avg_revenue_per_product * 100.0 / r.region_total_avg_revenue, 2) AS normalized_percent_contribution
FROM normalized n
JOIN region_totals r ON n.region = r.region
ORDER BY n.region, normalized_percent_contribution DESC;
-- Calculates avg revenue per product by region and category, adjusting for variety count.
-- Then computes each category's normalized % contribution to regional revenue.


WITH product_performance AS (
    SELECT 
        s.product_id,
        p.category,
        AVG(s.units_sold) AS avg_units_sold
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    GROUP BY s.product_id, p.category
)
SELECT 
    product_id,
    category,
    ROUND(avg_units_sold, 2) AS avg_units_sold,
    CASE
        WHEN avg_units_sold >= 105.39 THEN 'Fast-Moving'
        WHEN avg_units_sold <= 89.03 THEN 'Slow-Moving'
        ELSE 'Medium-Moving'
    END AS movement_category
FROM product_performance
ORDER BY movement_category, avg_units_sold DESC;



WITH sales_with_month AS (
    SELECT 
        s.*,
        MONTH(s.date) AS month
    FROM sales s),
sales_with_season AS (
    SELECT 
        swm.product_id,
        swm.units_sold,
        swm.revenue,
        sea.season
    FROM sales_with_month swm
    JOIN seasons sea ON swm.month = sea.month)
SELECT 
    product_id,
    season,
    SUM(units_sold) AS total_units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM sales_with_season
GROUP BY product_id, season
ORDER BY product_id, season;
-- demonstrating sales of each product seasonaly


WITH sales_with_month AS (
    SELECT 
        s.*,
        MONTH(s.date) AS month
    FROM sales s
),
sales_with_season AS (
    SELECT 
        swm.product_id,
        swm.units_sold,
        swm.revenue,
        sea.season
    FROM sales_with_month swm
    JOIN seasons sea ON swm.month = sea.month
),
sales_with_category AS (
    SELECT 
        s.product_id,
        p.category,
        s.units_sold,
        s.revenue,
        s.season
    FROM sales_with_season s
    JOIN products p ON s.product_id = p.product_id
)
SELECT 
    category,
    season,
    SUM(units_sold) AS total_units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM sales_with_category
GROUP BY category, season
ORDER BY category, season;
-- demonstrating sales of each category seasonaly

-- top products per region
SELECT 
	region, 
    product_id, 
    SUM(units_sold) as total_units_sold 
FROM sales
GROUP BY region, product_id 
ORDER BY total_units_sold DESC LIMIT 10;


-- =================== --
-- Store based analysis --
-- =================== --
-- Store based analysis

SELECT store_id, SUM(revenue) as total_rev FROM sales 
GROUP BY store_id 
ORDER BY total_rev DESC;

SELECT store_id, AVG(revenue) as avg_rev_per_dat 
FROM sales 
GROUP BY store_id 
ORDER BY avg_rev_per_dat DESC;
-- avg daily revenue ranges from 4942 for store5 followed by 4,1,3 then lowest 4900 for store2

SELECT store_id, AVG(units_sold) as avg_soldunits_perday 
FROM sales 
GROUP BY store_id 
ORDER BY avg_soldunits_perday DESC;
-- very less difference for avg sales of unit 96.84 being higest for store5 followed by store 3, then  4 then 2 96.59 for store1
-- This shows store 4 and 1 have good pricings and store 3 has poor pricing strategy

SELECT store_id, SUM(units_sold) as total_unitsold 
FROM sales 
GROUP BY store_id 
ORDER BY total_unitsold DESC;

SELECT
    store_id,
    YEAR(date) AS year,
    SUM(CASE WHEN MONTH(date) = 1 THEN revenue ELSE 0 END) AS Jan,
    SUM(CASE WHEN MONTH(date) = 2 THEN revenue ELSE 0 END) AS Feb,
    SUM(CASE WHEN MONTH(date) = 3 THEN revenue ELSE 0 END) AS Mar,
    SUM(CASE WHEN MONTH(date) = 4 THEN revenue ELSE 0 END) AS Apr,
    SUM(CASE WHEN MONTH(date) = 5 THEN revenue ELSE 0 END) AS May,
    SUM(CASE WHEN MONTH(date) = 6 THEN revenue ELSE 0 END) AS Jun,
    SUM(CASE WHEN MONTH(date) = 7 THEN revenue ELSE 0 END) AS Jul,
    SUM(CASE WHEN MONTH(date) = 8 THEN revenue ELSE 0 END) AS Aug,
    SUM(CASE WHEN MONTH(date) = 9 THEN revenue ELSE 0 END) AS Sep,
    SUM(CASE WHEN MONTH(date) = 10 THEN revenue ELSE 0 END) AS Oct,
    SUM(CASE WHEN MONTH(date) = 11 THEN revenue ELSE 0 END) AS Nov,
    SUM(CASE WHEN MONTH(date) = 12 THEN revenue ELSE 0 END) AS `Dec`
FROM sales
WHERE YEAR(date) IN (2022, 2023)
GROUP BY store_id, YEAR(date)
ORDER BY store_id, year;
-- this gives table for sales for stores in different months

-- inventory turnover
WITH daily_store_inventory AS (
    SELECT 
        store_id,
        date,
        SUM(units_sold) AS daily_units_sold,
        SUM(inventory_level) AS daily_inventory_level
    FROM sales
    GROUP BY store_id, date)
SELECT 
    store_id,
    ROUND(SUM(daily_units_sold) / NULLIF(AVG(daily_inventory_level), 0), 2) AS avg_inventory_turnover
FROM daily_store_inventory
GROUP BY store_id;

-- checking where the inventory lvl was less than the demand forecasted
SELECT COUNT(*) FROM sales WHERE inventory_level < demand_forecast;
-- 26272 instances of inventory lvl less than demand forecast

SELECT ROUND(SUM((demand_forecast - units_sold) * price), 2) AS estimated_lost_revenue
FROM sales
WHERE inventory_level < demand_forecast;
-- so if actual sale would have been equal to forecast 18974795.14 much revenue could have been lost

SELECT COUNT(*) FROM sales WHERE inventory_level < units_sold;
-- 5545 rows have less inventory than units sold, this could have caused some extra cost to the store for quick replenishing the
-- stock or they might have delivered that from warehouse rather than store

SELECT store_id, COUNT(*) AS understock_events
FROM sales
WHERE inventory_level < units_sold
GROUP BY store_id
ORDER BY understock_events DESC;
-- this demonstrate events where inventory lvl was less than units solds, means the stores made instant arragements to deliver it
-- this increases overall cost due to increase transport etc costs, so less profit
-- Store 4 tops this with 1180 which isnt good sign for inventory management, 3 having lowest 1075 which could also be lowered 

SELECT ROUND(SUM(inventory_level - units_sold),2) AS total_lost_units
FROM sales
WHERE inventory_level < demand_forecast;

WITH yearly_rev AS (
  SELECT store_id, YEAR(date) AS year, SUM(revenue) AS total_rev
  FROM sales
  GROUP BY store_id, YEAR(date)
)
SELECT 
    a.store_id,
    a.total_rev AS rev_2022,
    b.total_rev AS rev_2023,
    ROUND(((b.total_rev - a.total_rev)/a.total_rev) * 100, 2) AS yoy_growth_percent
FROM yearly_rev a
JOIN yearly_rev b ON a.store_id = b.store_id AND a.year = 2022 AND b.year = 2023;

WITH base_metrics AS (
    SELECT 
        store_id,
        SUM(revenue) AS total_revenue,
        ROUND(SUM(units_sold) / NULLIF(AVG(inventory_level), 0), 2) AS inventory_turnover,
        SUM(CASE WHEN inventory_level < demand_forecast THEN 1 ELSE 0 END) AS understock_events
    FROM sales
    GROUP BY store_id
)
, min_max AS (
    SELECT
        MIN(total_revenue) AS min_rev,
        MAX(total_revenue) AS max_rev,
        MIN(inventory_turnover) AS min_turn,
        MAX(inventory_turnover) AS max_turn,
        MIN(understock_events) AS min_under,
        MAX(understock_events) AS max_under
    FROM base_metrics
)
SELECT 
    b.store_id,
    ROUND(
        (
            0.5 * ((b.total_revenue - m.min_rev) / NULLIF((m.max_rev - m.min_rev), 0)) +
            0.3 * ((b.inventory_turnover - m.min_turn) / NULLIF((m.max_turn - m.min_turn), 0)) +
            0.2 * (1 - ((b.understock_events - m.min_under) / NULLIF((m.max_under - m.min_under), 0)))
        ) * 100, 2
    ) AS performance_score
FROM base_metrics b
CROSS JOIN min_max m
ORDER BY performance_score DESC;

-- ==================== --
-- Pricing and Promo analysis --
-- ==================== --
SELECT
    CASE
        WHEN discount = 0 THEN 'No Discount (0%)'
        WHEN discount BETWEEN 1 AND 5 THEN 'Low Discount (1-5%)'
        WHEN discount BETWEEN 6 AND 10 THEN 'Moderate Discount (6-10%)'
        WHEN discount BETWEEN 11 AND 15 THEN 'High Discount (11-15%)'
        WHEN discount BETWEEN 16 AND 20 THEN 'Very High Discount (16-20%)'
    END AS discount_range,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    ROUND(AVG(revenue), 2) AS avg_revenue,
    COUNT(*) AS num_sales_events
FROM sales
GROUP BY discount_range
ORDER BY avg_units_sold;
-- as discount incr avg revenue decr
-- surprisingly moderate disc has most units sold on avg just 0,01 greaterthan very high disc

SELECT
    store_id,
    CASE
        WHEN discount = 0 THEN 'No Discount (0%)'
        WHEN discount BETWEEN 1 AND 5 THEN 'Low (1–5%)'
        WHEN discount BETWEEN 6 AND 10 THEN 'Moderate (6–10%)'
        WHEN discount BETWEEN 11 AND 15 THEN 'High (11–15%)'
        WHEN discount BETWEEN 16 AND 20 THEN 'Very High (16–20%)'
    END AS discount_range,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    ROUND(AVG(revenue), 2) AS avg_revenue
FROM sales
GROUP BY store_id, discount_range
ORDER BY store_id, avg_revenue;

SELECT
    product_id,
    CASE
        WHEN discount = 0 THEN 'No Discount (0%)'
        WHEN discount BETWEEN 1 AND 5 THEN 'Low (1–5%)'
        WHEN discount BETWEEN 6 AND 10 THEN 'Moderate (6–10%)'
        WHEN discount BETWEEN 11 AND 15 THEN 'High (11–15%)'
        WHEN discount BETWEEN 16 AND 20 THEN 'Very High (16–20%)'
    END AS discount_range,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    ROUND(AVG(revenue), 2) AS avg_revenue
FROM sales
GROUP BY product_id, discount_range
ORDER BY product_id, discount_range;

SELECT
    store_id,
    product_id,
    discount,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    ROUND(AVG(revenue), 2) AS avg_revenue
FROM sales
GROUP BY store_id, product_id, discount
ORDER BY store_id, product_id, discount;

SELECT
    ROUND(AVG(competitor_pricing - price), 2) AS avg_price_diff,
    ROUND(AVG(units_sold), 2) AS avg_units_sold
FROM sales
GROUP BY 
    CASE 
        WHEN (competitor_pricing - price) > 5 THEN 'Much Cheaper'
        WHEN (competitor_pricing - price) BETWEEN 1 AND 5 THEN 'Slightly Cheaper'
        WHEN (competitor_pricing - price) BETWEEN -5 AND -1 THEN 'Slightly Expensive'
        WHEN (competitor_pricing - price) < -5 THEN 'Much Expensive'
        ELSE 'Same Price'
    END;
    
    -- Simplified elasticity estimation using linear regression (if available in your SQL environment)
-- Otherwise export to Python/Excel for regression
-- have to do it in python

-- ==================== --
-- Inventory optimise-- 
-- =================== --

-- 🔹 1. Reorder Points (ROP = 7 * avg daily demand)
CREATE OR REPLACE VIEW reorder_points AS
SELECT 
    product_id,
    ROUND(AVG(units_sold) * 7, 2) AS reorder_point
FROM sales_data
GROUP BY product_id;

--  Reorder Point (ROP) analysis shows most products need stock replenishment when average weekly demand approaches 600–740 units.
--  High ROPs (e.g., >730) suggest popular or fast-moving items that require tighter inventory monitoring to avoid stockouts.

-- 🔹 2. Products Below Reorder Point
SELECT 
    s.product_id,
    s.store_id,
    s.date,
    s.inventory_level,
    r.reorder_point
FROM sales_data s
JOIN reorder_points r ON s.product_id = r.product_id
WHERE s.inventory_level <= r.reorder_point;

-- These products are below their reorder points, meaning they might run out of stock soon.
-- It looks like many items across all stores had low inventory on the same date (2022-01-01).
-- This could mean the starting stock was too low or the demand was higher than expected.

-- 🔹 3. Inventory Age Tracking – Detect stock level changes using LAG
SELECT 
    product_id,
    store_id,
    date,
    inventory_level,
    LAG(inventory_level) OVER (PARTITION BY product_id, store_id ORDER BY date) AS previous_level,
    CASE 
        WHEN inventory_level != LAG(inventory_level) OVER (PARTITION BY product_id, store_id ORDER BY date)
        THEN date
        ELSE NULL
    END AS stock_change_date
FROM sales_data;

--  shows how inventory levels changed each day for product P0016 in store S001.
--  We can clearly see frequent stock fluctuations, with almost every day showing a different inventory level.
--  Using LAG helped track when stock levels changed — useful to analyze replenishment or demand spikes.

-- 🔹 4. Most Recent Stock Change per Product-Store
SELECT *
FROM (
    SELECT 
        product_id,
        store_id,
        date AS last_stock_change_date,
        ROW_NUMBER() OVER (PARTITION BY product_id, store_id ORDER BY date DESC) AS rn
    FROM (
        SELECT 
            product_id,
            store_id,
            date,
            inventory_level,
            LAG(inventory_level) OVER (PARTITION BY product_id, store_id ORDER BY date) AS previous_level
        FROM sales_data
    ) changes
    WHERE inventory_level != previous_level
) latest_changes
WHERE rn = 1;

-- 🔹 5. Safety Stock (2 * stddev of demand)
CREATE OR REPLACE VIEW safety_stock AS
SELECT 
    product_id,
    ROUND(STDDEV(units_sold) * 2, 2) AS safety_stock_level
FROM sales_data
GROUP BY product_id;

-- 🔹 6. Service Level (% of days demand was fulfilled)
CREATE OR REPLACE VIEW service_level AS
SELECT 
    product_id,
    COUNT(*) AS total_days,
    SUM(CASE WHEN inventory_level >= units_sold THEN 1 ELSE 0 END) AS fulfilled_days,
    ROUND(SUM(CASE WHEN inventory_level >= units_sold THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS service_level_percent
FROM sales_data
GROUP BY product_id;

-- 🔹 7. EOQ (Economic Order Quantity, using constants)
-- D = annual demand (units_sold), S = ordering cost (₹50), H = holding cost/unit/year (₹10)
CREATE OR REPLACE VIEW economic_order_quantity AS
SELECT 
    product_id,
    ROUND(SQRT((2 * SUM(units_sold) * 50) / 10), 2) AS eoq_units
FROM sales_data
GROUP BY product_id;

-- 🔹 8. Stockout Rate (% of days inventory < units sold)
CREATE OR REPLACE VIEW stockout_rate AS
SELECT 
    product_id,
    COUNT(*) AS total_days,
    SUM(CASE WHEN inventory_level < units_sold THEN 1 ELSE 0 END) AS stockout_days,
    ROUND(SUM(CASE WHEN inventory_level < units_sold THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS stockout_rate_percent
FROM sales_data
GROUP BY product_id;

-- 🔹 9. Inventory Turnover Ratio
CREATE OR REPLACE VIEW inventory_turnover AS
SELECT 
    product_id,
    ROUND(SUM(units_sold) / NULLIF(AVG(inventory_level), 0), 2) AS inventory_turnover_ratio
FROM sales_data
GROUP BY product_id;

-- 🔹 10. ABC Classification by Revenue (Pareto Principle)
CREATE OR REPLACE VIEW abc_classification AS
WITH product_revenue AS (
    SELECT 
        product_id,
        SUM(units_sold * price) AS total_revenue
    FROM sales_data
    GROUP BY product_id
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY total_revenue DESC) AS rnk,
           SUM(total_revenue) OVER () AS total
    FROM product_revenue
),
classified AS (
    SELECT *,
           ROUND((total_revenue / total) * 100, 2) AS revenue_percent
    FROM ranked
)
SELECT *,
       CASE
           WHEN revenue_percent >= 80 THEN 'A'
           WHEN revenue_percent >= 15 THEN 'B'
           ELSE 'C'
       END AS abc_class
FROM classified;

-- 🔹 11. Final Inventory Optimization Dashboard View
CREATE OR REPLACE VIEW inventory_dashboard AS
SELECT 
    r.product_id,
    r.reorder_point,
    ss.safety_stock_level,
    eo.eoq_units,
    sl.service_level_percent,
    sr.stockout_rate_percent,
    it.inventory_turnover_ratio,
    abc.abc_class
FROM reorder_points r
JOIN safety_stock ss ON r.product_id = ss.product_id
JOIN economic_order_quantity eo ON r.product_id = eo.product_id
JOIN service_level sl ON r.product_id = sl.product_id
JOIN stockout_rate sr ON r.product_id = sr.product_id
JOIN inventory_turnover it ON r.product_id = it.product_id
JOIN abc_classification abc ON r.product_id = abc.product_id;

--  Query the final summary:
SELECT * FROM inventory_dashboard ORDER BY stockout_rate_percent DESC;

-- ===================== --
-- Forecast analysis
-- ===================== --

-- 🔹 1. Forecast Trends by Month, Season, and Holiday
SELECT 
    d.month, 
    s2.season, 
    d.holiday_flag,
    AVG(s.demand_forecast) AS avg_forecast,
    AVG(s.units_sold) AS avg_units_sold
FROM sales_data s
JOIN dates d ON s.date = d.date
JOIN seasons s2 ON d.month = s2.month
GROUP BY d.month, s2.season, d.holiday_flag
ORDER BY d.month;

--  The model tends to over-forecast during non-holidays, with ~12 units gap on average.
--  Winter months (Jan, Feb, Nov, Dec) have highest forecasts, likely due to seasonal overestimation.
--  Shows a pattern of bias — model may need tuning for better seasonal accuracy.



-- 🔹 2. Compare Average Forecast vs Units Sold Over Time
SELECT 
    s.date,
    AVG(s.demand_forecast) AS avg_forecast,
    AVG(s.units_sold) AS avg_units_sold
FROM sales_data s
GROUP BY s.date
ORDER BY s.date;

SELECT 
    d.holiday_flag,
    ROUND(AVG(ABS(s.units_sold - s.demand_forecast)), 2) AS avg_mae,
    ROUND(AVG(ABS((s.units_sold - s.demand_forecast) / NULLIF(s.units_sold, 0))) * 100, 2) AS avg_mape,
    COUNT(*) AS total_records
FROM sales_data s
JOIN dates d ON s.date = d.date
GROUP BY d.holiday_flag;

-- For non-holidays:
--   Average MAE = 13.74 units → Model over- or under-predicts demand by ~13.74 units on average.
--   Average MAPE = 15.82% → Forecast error is about 15.8% relative to actual sales.
--   Total Records = 109,500 → All data points are non-holiday, suggesting holiday flags were not set or populated


-- 🔹 3. Analyze Impact of Discount on Forecast Accuracy
SELECT 
    ROUND(s.discount, 2) AS discount_percent,
    AVG(ABS(s.units_sold - s.demand_forecast)) AS avg_forecast_error
FROM sales_data s
GROUP BY ROUND(s.discount, 2)
ORDER BY discount_percent;

-- Across all discount levels (0% to 20%), the average forecast error (MAE) stays roughly constant around ~13.7 units.
-- This suggests that the current forecasting model may not be effectively incorporating discount sensitivity.


-- 🔹 4. Correlate Forecast Error with Discount
SELECT 
    s.product_id,
    s.date,
    s.discount,
    (s.units_sold - s.demand_forecast) AS forecast_error
FROM sales_data s
ORDER BY s.discount DESC;

-- Forecast Errors at 20% Discount
-- All rows are from 20% discount cases, but errors vary a lot.
-- Big negative errors mean the model overestimated demand even with discounts.
-- Some positive errors suggest the model didn’t catch the boost in demand from discounts.



-- 🔹 5. Regional Variation in Forecast Accuracy
-- Evaluates how well the forecast performs in different regions by comparing actual vs. forecasted sales.
SELECT 
    s.region,
    AVG(ABS(s.units_sold - s.demand_forecast)) AS avg_forecast_error
FROM sales_data s
GROUP BY s.region
ORDER BY avg_forecast_error DESC;

-- South region shows the highest average forecast error (~13.80), indicating underperformance in prediction accuracy.
-- North and West regions follow closely, with slightly lower errors (~13.74 and ~13.73).
-- East region has the lowest average forecast error (~13.68), suggesting the model is most accurate here.

