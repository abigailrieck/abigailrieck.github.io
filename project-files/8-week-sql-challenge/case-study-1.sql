-- Case study 1: analyzing data from a fictional Japanese restaurant, Danny's Diner

-- Case Study Questions

-- #1: What is the total amount each customer spent at the restaurant?
SELECT customer_id, SUM(price) AS total_spent
FROM dannys_diner.sales AS s
LEFT JOIN dannys_diner.menu AS m
ON s.product_id = m.product_id
GROUP BY customer_id
ORDER BY customer_id;

-- #2: How many days has each customer visited the restaurant?
SELECT customer_id, COUNT(DISTINCT order_date) AS days_visited
FROM dannys_diner.sales AS s
LEFT JOIN dannys_diner.menu AS m
ON s.product_id = m.product_id
GROUP BY customer_id
ORDER BY customer_id;

-- #3: What was the first item from the menu purchased by each customer?
SELECT customer_id, product_name AS first_item
	FROM(
	SELECT customer_id, product_name, ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY order_date)
	FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	)
WHERE row_number = 1;

-- #4: What is the most purchased item on the menu and how many times was it purchased 
-- by all customers?
SELECT product_name AS most_purchased, COUNT(*) AS times_purchased
FROM dannys_diner.sales AS s
LEFT JOIN dannys_diner.menu AS m
ON s.product_id = m.product_id
GROUP BY product_name
ORDER BY 2 DESC
LIMIT 1;

-- #5: Which item was the most popular for each customer?
SELECT customer_id, product_name AS most_ordered
FROM (SELECT customer_id, product_name, COUNT(*) AS count,
	ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY COUNT(*) DESC)
	FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	GROUP BY customer_id, product_name
	)
WHERE row_number = 1;

-- #6: Which item was purchased first by the customer after they became a member?
SELECT sub.customer_id, product_name AS first_item
	FROM(
	SELECT s.customer_id, product_name, ROW_NUMBER() OVER(PARTITION BY s.customer_id ORDER BY s.order_date)
 	FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	LEFT JOIN dannys_diner.members AS me
	ON s.customer_id = me.customer_id
	WHERE order_date > join_date
	) AS sub
WHERE row_number = 1;

-- #7: Which item was purchased just before the customer became a member?
SELECT customer_id, product_name
	FROM(
	SELECT s.customer_id, product_name, order_date, ROW_NUMBER() OVER(PARTITION BY s.customer_id ORDER BY s.order_date DESC)
 	FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	LEFT JOIN dannys_diner.members AS me
	ON s.customer_id = me.customer_id
	WHERE order_date < join_date
	) AS sub
WHERE row_number = 1
;

-- #8: What is the total items and amount spent for each member before they became a member?
SELECT s.customer_id, COUNT(*) AS total_items, SUM(price) AS amount_spent
FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	LEFT JOIN dannys_diner.members AS me
	ON s.customer_id = me.customer_id
WHERE order_date < join_date
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- #9: If each $1 spent equates to 10 points and sushi has a 2x points multiplier - 
-- how many points would each customer have?
SELECT customer_id, SUM(points) AS total_points
	FROM (
SELECT *, 
	CASE WHEN product_name = 'sushi' THEN price * 10 *2
	ELSE price * 10 END AS points
FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	)
GROUP BY customer_id
	ORDER BY customer_id;

-- #10: In the first week after a customer joins the program (including their join date) they 
-- earn 2x points on all items, not just sushi - how many points do customer A and B have at 
-- the end of January?
WITH promo AS (SELECT customer_id, join_date, 
			join_date + INTERVAL '1 week' AS end_promo
	FROM dannys_diner.members),
	points AS (
		SELECT s.customer_id,
		CASE WHEN (product_name = 'sushi') OR
				(order_date BETWEEN join_date AND end_promo)
				THEN price * 10 *2
			ELSE price * 10 END AS points_earned
	FROM dannys_diner.sales AS s
	LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
	LEFT JOIN promo AS p
	ON s.customer_id = p.customer_id
	)
SELECT s.customer_id, SUM(points_earned) AS total_points
FROM dannys_diner.sales AS s
	LEFT JOIN points AS po
	ON s.customer_id = po.customer_id
WHERE order_date < '2021-02-01' AND s.customer_id IN ('A', 'B')
GROUP BY s.customer_id;


-- Bonus Questions

-- "Join all the things"- recreate table given in prompt
SELECT s.customer_id,
	order_date,
	product_name,
	price,
	CASE WHEN order_date >= join_date THEN 'Y'
		ELSE 'N' END AS member
FROM dannys_diner.sales AS s
LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
LEFT JOIN dannys_diner.members AS me
	ON s.customer_id = me.customer_id
ORDER BY customer_id, order_date;

-- "Rank all the things"- recreate table given in prompt
WITH t1 AS (SELECT s.customer_id,
	order_date,
	product_name,
	price,
	CASE WHEN order_date >= join_date THEN 'Y'
		ELSE 'N' END AS member
FROM dannys_diner.sales AS s
LEFT JOIN dannys_diner.menu AS m
	ON s.product_id = m.product_id
LEFT JOIN dannys_diner.members AS me
	ON s.customer_id = me.customer_id
	),
t2 AS (SELECT customer_id, order_date, RANK() OVER(PARTITION BY customer_id ORDER BY order_date)
	FROM t1
	WHERE member = 'Y')
SELECT t1.customer_id,
	t1.order_date,
	t1.product_name,
	t1.price,
	t1.member,
	CASE WHEN t1.member = 'Y' THEN t2.rank
		ELSE null END AS ranking
FROM t1
LEFT JOIN t2
	ON t1.customer_id = t2.customer_id AND t1.order_date = t2.order_date
ORDER BY t1.customer_id, order_date;