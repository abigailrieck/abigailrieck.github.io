-- Solution to Case Study #7 from Data with Danny's 8-week SQL challenge: https://8weeksqlchallenge.com/case-study-7/
-- Analyzing sales performance for a fictional clothing company 


-- Starting by creating a temporary table to store revenue and discount amts for each 
-- row, along with revenue for each transaction
DROP TABLE IF EXISTS revenues
	
CREATE TEMPORARY TABLE revenues AS
	SELECT *,
	qty * price::numeric AS pre_discount,
	qty * price * discount * .01 AS disc_amt,
	qty * (price - (price * discount * .01)) AS item_rev,
	SUM(qty * (price - (price * discount * .01))) OVER(PARTITION BY txn_id) AS txn_rev
	FROM balanced_tree.sales;

SELECT * FROM revenues
	

--High level sales analysis

-- Total quantity sold
SELECT SUM(qty) AS total_qty_sold
FROM balanced_tree.sales;

-- Total revenue before discounts; sum of quantity times price
SELECT SUM(pre_discount) AS total_rev_pre_discount
FROM revenues;

-- Total discount amount for all products
SELECT SUM(disc_amt) AS total_discounts
FROM revenues;


--Transaction analysis

-- Number of unique transactions
SELECT COUNT(DISTINCT(txn_id))
FROM balanced_tree.sales;

-- Average # of unique products per transaction
SELECT ROUND(AVG(count),2) AS avg_products
FROM (
	SELECT COUNT(*) AS count
	FROM balanced_tree.sales
	GROUP BY txn_id
);

-- 25th, 50th, and 75th percentiles of revenue per transaction
SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY txn_rev) AS pct_25,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY txn_rev) AS pct_50,
	PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY txn_rev) AS pct_75
FROM revenues;

-- Average discount value per transaction
SELECT ROUND(AVG(txn_disc),2) AS avg_discount
FROM (SELECT SUM(disc_amt) AS txn_disc
	FROM revenues
	GROUP BY txn_id);

-- Percentage split of transactions for members vs non members
SELECT member, ROUND(100.0*COUNT(DISTINCT(txn_id))::numeric/(SELECT COUNT(DISTINCT(txn_id)) FROM balanced_tree.sales),2)
	AS percentage
FROM balanced_tree.sales
GROUP BY member;

-- Average revnue for member and non-member transactions
WITH member_revs AS (SELECT DISTINCT s.txn_id, s.member, r.txn_rev
	FROM balanced_tree.sales AS s
	LEFT JOIN revenues AS r
	ON s.txn_id = r.txn_id)
SELECT ROUND(AVG(txn_rev),2)
	FROM member_revs
	GROUP BY member;


-- Product Analysis

--Top 3 products by revenue before discount
SELECT product_name
FROM balanced_tree.product_details
WHERE product_id IN (
	SELECT prod_id
	FROM revenues
	GROUP BY prod_id
	ORDER BY SUM(pre_discount) DESC
	LIMIT 3
)

-- Total quantity, revenue, and discount per segment
SELECT segment_name,
	SUM(qty) AS quantity,  
	SUM(item_rev) AS revenue,
	SUM(disc_amt) AS discount
FROM revenues AS r
LEFT JOIN balanced_tree.product_details AS p
ON r.prod_id = p.product_id
GROUP BY segment_name;

-- Top selling item per segment
SELECT segment_name, product_name, quantity
	FROM(
	SELECT segment_name, product_name,
	SUM(qty) AS quantity,
	ROW_NUMBER() OVER(PARTITION BY segment_name ORDER BY SUM(qty) DESC)
	FROM revenues AS r
	LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
	GROUP BY p.product_name, p.segment_name
	)
WHERE row_number = 1;

-- Total quantity, revenue, and discount by category
SELECT category_name,
	SUM(qty) AS quantity,  
	SUM(item_rev) AS revenue,
	SUM(disc_amt) AS discount
FROM revenues AS r
LEFT JOIN balanced_tree.product_details AS p
ON r.prod_id = p.product_id
GROUP BY category_name;

-- Top selling product by category
SELECT category_name, product_name, quantity
	FROM(
	SELECT category_name, product_name,
	SUM(qty) AS quantity,
	ROW_NUMBER() OVER(PARTITION BY category_name ORDER BY SUM(qty) DESC)
	FROM revenues AS r
	LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
	GROUP BY p.product_name, p.category_name
	)
WHERE row_number = 1;

-- Percentage split of revenue by product for each segment
WITH prod_rev AS (
	SELECT p.product_name, p.segment_name, SUM(r.item_rev) AS tot_prod_rev
	FROM revenues AS r
	LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
	GROUP BY product_name, segment_name
)
SELECT segment_name, product_name,
ROUND(100*tot_prod_rev/SUM(tot_prod_rev) OVER(PARTITION BY segment_name),2) AS pct_segment_revenue
FROM prod_rev;

-- Percentage split of revenue by segment for each category
WITH seg_rev AS (
	SELECT p.segment_name, p.category_name, SUM(r.item_rev) AS tot_seg_rev
	FROM revenues AS r
	LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
	GROUP BY segment_name, category_name
)
SELECT category_name, segment_name,
ROUND(100*tot_seg_rev/SUM(tot_seg_rev) OVER(PARTITION BY category_name),2) AS pct_category_revenue
FROM seg_rev;

-- Percentage split of total revenue by category
SELECT category_name,
ROUND(100*SUM(item_rev)/(SELECT SUM(item_rev) FROM revenues),2) AS pct_revenue
FROM revenues AS r
LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
GROUP BY category_name;

--Transaction penetration for each product-- % of transactions where each product was sold
SELECT product_name, 
ROUND(1.0*COUNT(*)/(SELECT COUNT(DISTINCT txn_id) FROM revenues),3) AS txn_penetration
FROM revenues AS r
	LEFT JOIN balanced_tree.product_details AS p
	ON r.prod_id = p.product_id
GROUP BY product_name
ORDER BY txn_penetration DESC;

-- Most common combination of any three items in a transaction
SELECT r1.prod_id, r2.prod_id, r3.prod_id, COUNT(*) AS combo_count
FROM revenues AS r1
JOIN revenues AS r2 ON r1.txn_id = r2.txn_id
	AND r1.prod_id < r2.prod_id
JOIN revenues AS r3 ON r3.txn_id = r1.txn_id
	AND r2.prod_id < r3.prod_id
GROUP BY r1.prod_id, r2.prod_id, r3.prod_id
ORDER BY combo_count DESC
	LIMIT 1;



