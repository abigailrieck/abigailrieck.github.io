-- setup and cleaning
--Fixing issues with null data in runner & customer order tables, trimming labels from distance and duration in runner order table and formatting pickup time as timestamp

SET search_path = pizza_runner

CREATE TEMP TABLE c_orders AS (
	SELECT order_id, customer_id, pizza_id,
   			NULLIF(NULLIF(exclusions, 'null'), '') AS exclusions,
  			NULLIF(NULLIF(extras, 'null'), '') AS extras,
			order_time
	FROM customer_orders
)

CREATE TEMP TABLE r_orders AS (
	SELECT order_id, runner_id,
	TO_TIMESTAMP(NULLIF(pickup_time, 'null'), 'YYYY-MM-DD HH24:MI:SS') AS pickup_time,
	CASE WHEN distance LIKE 'null' THEN NULL
          WHEN distance LIKE '%km' THEN TRIM(distance,'km') 
          ELSE distance END AS distance,
	CASE WHEN duration LIKE 'null' THEN NULL
		WHEN duration LIKE '%minutes' THEN TRIM(duration, 'minutes')
		WHEN duration LIKE '%mins' THEN TRIM (duration, 'mins')
		WHEN duration LIKE '%minute' THEN TRIM (duration, 'minute')
		ELSE duration END AS duration,
	NULLIF(NULLIF(cancellation, 'null'), '') AS cancellation	
	FROM runner_orders
)

CREATE TEMP TABLE cancelled_orders AS (
	SELECT order_id
	FROM r_orders
	WHERE cancellation IS NOT NULL
	)

	
--- Section A: Pizza Metrics

-- 1. How many pizzas were ordered?
SELECT COUNT(pizza_id) FROM c_orders;

--2. How many unique customer orders were made?
SELECT COUNT(DISTINCT order_id) FROM c_orders;

--3. How many succesful orders were delivered by each runner?
SELECT runner_id, COUNT (*) AS delivered_orders
FROM r_orders
WHERE cancellation IS NULL
GROUP BY runner_id;

--4. How many of each type of pizza was delivered?
SELECT pizza_name, COUNT(*) 
FROM c_orders AS c
	LEFT JOIN pizza_names AS p
	ON c.pizza_id = p.pizza_id
WHERE order_id NOT IN (SELECT * FROM cancelled_orders)
GROUP BY pizza_name;

--5. How many Vegetarian and Meatlovers were ordered by each customer?
SELECT customer_id, pizza_name, COUNT(*) 
FROM c_orders AS c
	LEFT JOIN pizza_names AS p
	ON c.pizza_id = p.pizza_id
WHERE order_id NOT IN (SELECT * FROM cancelled_orders)
GROUP BY customer_id, pizza_name;

--6. What was the maximum number of pizzas delivered in a single order?
WITH counts AS (SELECT COUNT(*) AS pizzas_delivered
FROM c_orders
WHERE order_id NOT IN (SELECT * FROM cancelled_orders)
GROUP BY order_id
	)
SELECT MAX(pizzas_delivered) FROM counts;

--7. For each customer, how many delivered pizzas had at least 1 change and how many had no changes?
WITH changes AS (SELECT customer_id,
	CASE WHEN exclusions IS NOT NULL OR extras IS NOT NULL THEN 'change'
	ELSE 'no change' END AS change
FROM c_orders
WHERE order_id NOT IN (SELECT * FROM cancelled_orders)
	)
SELECT customer_id, change, COUNT(*) 
FROM changes
GROUP BY customer_id, change;

--8. How many pizzas were delivered that had both exclusions and extras?
SELECT COUNT(*) AS multiple_changes
FROM c_orders
WHERE exclusions IS NOT NULL AND extras IS NOT NULL
	AND order_id NOT IN (SELECT * FROM cancelled_orders);

--9. What was the total volume of pizzas ordered for each hour of the day?

WITH hour_series AS (SELECT generate_series(0,23) AS hour),
	c_hours AS (SELECT COUNT(*) AS n_ordered,
						EXTRACT(hour FROM order_time) AS hour
				FROM c_orders
				GROUP BY EXTRACT(hour FROM order_time)
	)
SELECT h.hour, COALESCE(n_ordered, 0)
FROM hour_series AS h
   LEFT JOIN c_hours AS c 
	ON h.hour = c.hour
ORDER BY h.hour;


	
--10. What was the total volume of orders for each day of the week?
WITH days AS (SELECT generate_series(0,6) AS day_num),
	c_days AS (SELECT EXTRACT(dow FROM order_time) AS day_num,
					COUNT(*) AS n_ordered
				FROM c_orders
				GROUP BY EXTRACT(dow FROM order_time)
	)
SELECT CASE WHEN d.day_num = 0 THEN 'Sunday'
			WHEN d.day_num = 1 THEN 'Monday'
			WHEN d.day_num = 2 THEN 'Tuesday'
			WHEN d.day_num = 3 THEN 'Wednesday'
			WHEN d.day_num = 4 THEN 'Thursday'
			WHEN d.day_num = 5 THEN 'Friday'
			WHEN d.day_num = 6 THEN 'Saturday' END AS day,
	COALESCE(n_ordered, 0) AS n_ordered
	FROM days AS d
	LEFT JOIN c_days AS c
	ON d.day_num = c.day_num
ORDER BY d.day_num;


---Section B: Runner and Customer Experience

--1. How many runners signed up for each 1 week period? 
SELECT EXTRACT(week FROM registration_date) AS week,
		COUNT(*) AS n_signed_up
FROM runners
GROUP BY EXTRACT(week FROM registration_date)
	ORDER BY EXTRACT(week FROM registration_date);

--2. What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
SELECT runner_id, TO_CHAR(AVG(pickup_time - order_time), 'MI:SS') AS avg_time_to_hq
FROM c_orders AS c
	LEFT JOIN r_orders AS r
ON c.order_id = r.order_id
GROUP BY runner_id
	ORDER BY runner_id;

--3. Is there any relationship between the number of pizzas and how long the order takes to prepare?
WITH pizzas AS (SELECT order_id, COUNT(*) as n_pizzas
				FROM c_orders 
				GROUP BY order_id),
	order_time AS (SELECT DISTINCT c.order_id, 
					EXTRACT(minute FROM pickup_time - order_time) AS prep_time
				FROM c_orders AS c
				LEFT JOIN r_orders AS r
				ON c.order_id = r.order_id)
SELECT corr(n_pizzas, prep_time) AS correlation
FROM pizzas AS p
	LEFT JOIN order_time AS o
	ON p.order_id = o.order_id;

--4. What was the average distance traveled for each customer?
SELECT customer_id, ROUND(AVG(distance::numeric),2)
FROM c_orders AS c
	LEFT JOIN r_orders AS r
	ON c.order_id = r.order_id
GROUP BY customer_id;

--5. What was the difference between the longest and shortest delivery times for all orders?
WITH times AS (SELECT pickup_time - order_time + duration::numeric * interval '1 minute' AS delivery_time
FROM c_orders AS c
	LEFT JOIN r_orders AS r
	ON c.order_id = r.order_id
  )
SELECT MAX(delivery_time) AS max,
	MIN(delivery_time) AS min,
	MAX(delivery_time) - MIN(delivery_time) AS difference
FROM times;

--6. What was the average speed for each runner for each delivery and do you notice any trend for these values?
SELECT runner_id, AVG((distance::numeric)/(duration::numeric)) AS avg_speed,
	AVG(distance::numeric) AS avg_dist
FROM r_orders
	GROUP BY runner_id;

--7. What is the successful delivery percentage for each runner?
SELECT runner_id, ROUND(COUNT(pickup_time)::numeric/COUNT(*)*100.00::numeric, 2) AS delivery_percentage
FROM r_orders
GROUP BY runner_id;


---Section C: Ingredient Optimization

--1. What are the standard ingredients for each pizza?
SELECT pizza_name, pt.topping_id, topping_name
FROM pizza_names AS pn
	JOIN pizza_recipes AS pr USING(pizza_id)
	JOIN LATERAL unnest(string_to_array(pr.toppings, ',')::INTEGER[]) AS t(topping_id) ON true
	JOIN pizza_toppings AS pt ON pt.topping_id = t.topping_id
ORDER BY pizza_name, topping_id;

--2. What was the most commonly added extra?
WITH extras_list AS (SELECT TRIM(unnest(string_to_array(extras, ','))) AS extra
	FROM c_orders)
SELECT topping_name, COUNT(*) AS times_added
FROM extras_list AS e
	LEFT JOIN pizza_toppings AS t
	ON e.extra::int = t.topping_id
GROUP BY topping_name
ORDER BY COUNT(*) DESC
LIMIT 1;

--3. What was the most common exclusion?
WITH exclusion_list AS (SELECT TRIM(unnest(string_to_array(exclusions, ','))) AS exclusion
	FROM c_orders)
SELECT topping_name, COUNT(*) AS times_removed
FROM exclusion_list AS e
	LEFT JOIN pizza_toppings AS t
	ON e.exclusion::int = t.topping_id
GROUP BY topping_name
ORDER BY COUNT(*) DESC
LIMIT 1;


--4. Generate an order item for each record in the customers_orders table in the format of one of the following: Meat Lovers, Meat Lovers - Exclude Beef, etc.

WITH c_orders AS (SELECT *,   --Add unique identifier for each pizza ordered
				ROW_NUMBER() OVER() AS item_id 
	FROM c_orders),
expanded1 AS (SELECT item_id,   --Expand extra & exclusion ids into their own rows
		TRIM(unnest(string_to_array(exclusions, ','))) AS exc_id,
		TRIM(unnest(string_to_array(extras, ','))) AS extra_id
	FROM c_orders
	),
expanded2 AS (SELECT item_id,  --Add in topping names to previous result
				exc_id, t1.topping_name AS exc_name,
				extra_id, t2.topping_name AS extra_name
		FROM expanded1 AS e1
			LEFT JOIN pizza_toppings AS t1
			ON e1.exc_id::int = t1.topping_id
			LEFT JOIN pizza_toppings AS t2
			ON e1.extra_id::int = t2.topping_id
	),
names AS (SELECT item_id,  --Aggregate topping names by pizza
		STRING_AGG(exc_name, ', ') AS excluded,
		STRING_AGG(extra_name, ', ') AS added
	FROM expanded2
	GROUP BY item_id
	)
SELECT order_id, customer_id, --Combine pizza name + topping names based on modifications
	CASE WHEN exclusions IS NULL AND extras IS NULL THEN pizza_name
	WHEN exclusions IS NULL AND extras IS NOT NULL THEN
		CONCAT(pizza_name, ' - Extra ', added)
	WHEN exclusions IS NOT NULL AND extras IS NULL THEN 
		CONCAT(pizza_name, ' - Exclude ', excluded)
	ELSE CONCAT(pizza_name, ' - Exclude ', excluded, ' - Extra ', added) END AS item,
	order_time
FROM c_orders AS orders
LEFT JOIN names AS n
ON orders.item_id = n.item_id
	LEFT JOIN pizza_names AS pn
ON orders.pizza_id = pn.pizza_id
	ORDER BY order_id;

--5. Generate an alphabetically ordered comma separated ingredient list for each pizza order from the customer_orders table and add a 2x in front of any relevant ingredients

WITH toppings AS (SELECT pizza_id, pr.topping_id, topping_name
	FROM (SELECT pizza_id,  --unnest topping list and join to ingredient names
		TRIM(unnest(string_to_array(toppings, ',')))::integer AS topping_id
		FROM pizza_recipes) AS pr
	LEFT JOIN pizza_toppings AS pt
ON pr.topping_id = pt.topping_id
ORDER BY pizza_id
	),
orders_numbered AS (SELECT *, ROW_NUMBER() OVER() AS item_id --add identifier
	FROM c_orders
	),
extras AS (SELECT item_id, --unnest extras into separate table
	TRIM(unnest(string_to_array(extras, ','))) AS extra_id
	FROM orders_numbered
	),
exclusions AS (SELECT item_id, --unnest esclusions into separate table
	TRIM(unnest(string_to_array(exclusions, ','))) AS exc_id
	FROM orders_numbered
	),
orders_expanded AS (SELECT o1.order_id, o1.item_id, o1.pizza_id, --cte with one row per ingredient, formatted with 2x before the name of any extras
	CASE WHEN topping_id IN (SELECT extra_id::integer --add 2x for ingredients in extras list
					FROM extras AS e1
					WHERE o1.item_id = e1.item_id)
	THEN CONCAT('2x', topping_name)
	ELSE topping_name END AS topping
FROM orders_numbered AS o1
	JOIN toppings AS t1
	ON o1.pizza_id = t1.pizza_id
	WHERE t1.topping_id NOT IN (SELECT exc_id::integer --exclude ingredients in exclusion list
					FROM exclusions AS e2
					WHERE o1.item_id = e2.item_id)
	ORDER BY topping ASC
	)	
SELECT ox.order_id, pn.pizza_name,
	STRING_AGG(topping,', ' ORDER BY topping) AS ingredients --aggregate ingredient rows into one string per pizza
FROM orders_expanded AS ox
	LEFT JOIN pizza_names AS pn
	ON ox.pizza_id = pn.pizza_id
GROUP BY item_id, ox.order_id, pn.pizza_name
ORDER BY order_id;
	
--6. What is the total quantity of each ingredient used in all delivered pizzas sorted by most frequent first?
WITH toppings AS (SELECT pizza_id, pr.topping_id, topping_name
	FROM (SELECT pizza_id,  --unnest topping list and join to ingredient names
		TRIM(unnest(string_to_array(toppings, ',')))::integer AS topping_id
		FROM pizza_recipes) AS pr
	LEFT JOIN pizza_toppings AS pt
ON pr.topping_id = pt.topping_id
ORDER BY pizza_id
	),
orders_numbered AS (SELECT *, ROW_NUMBER() OVER() AS item_id --add identifier
	FROM c_orders
	),
extras AS (SELECT item_id, --unnest extras into separate table
	TRIM(unnest(string_to_array(extras, ','))) AS extra_id
	FROM orders_numbered
	),
exclusions AS (SELECT item_id, --unnest esclusions into separate table
	TRIM(unnest(string_to_array(exclusions, ','))) AS exc_id
	FROM orders_numbered
	),
all_toppings AS( --generate master list of all toppings used with duplicate rows for extras and items removed for exclusions
	SELECT item_id, extra_id::integer AS topping_id, topping_name AS topping
	FROM extras AS e1
	LEFT JOIN pizza_toppings AS pt
	ON e1.extra_id::integer = pt.topping_id
UNION ALL 
	SELECT item_id, topping_id, topping_name
	FROM orders_numbered AS o1
	LEFT JOIN toppings AS t1
	ON o1.pizza_id = t1.pizza_id
	WHERE t1.topping_id NOT IN (SELECT exc_id::integer 
									FROM exclusions AS e2
									WHERE o1.item_id = e2.item_id)
	ORDER BY item_id
	)
SELECT topping, COUNT(*) AS qty_used
	FROM all_toppings
	GROUP BY topping
	ORDER BY COUNT(*) DESC;


--Section D: Pricing and Ratings

--1. If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - how much money has Pizza Runner made so far if there are no delivery fees?
CREATE TEMP TABLE sales AS (
	SELECT *,
	CASE WHEN pizza_id = 1 THEN 12
	WHEN pizza_id = 2 THEN 10 END AS price
	FROM c_orders)

SELECT SUM(price) AS sales_total
	FROM sales;

--2. What if there was an additional $1 charge for any pizza extras?
		--Add cheese is $1 extra
SELECT 
	SUM(CASE WHEN extras IS NOT NULL
	THEN array_length(string_to_array(extras, ','), 1) + price
	ELSE price END) AS sales_total
FROM sales

--3. The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, how would you design an additional table for this new dataset - generate a schema for this new table and insert your own data for ratings for each successful customer order between 1 to 5.

DROP TABLE IF EXISTS runner_ratings
	
CREATE TABLE pizza_runner.runner_ratings(
	order_id INTEGER,
	customer_id INTEGER,
	runner_id INTEGER,
	rating INTEGER
	);

INSERT INTO runner_ratings
	SELECT DISTINCT order_id, customer_id
	FROM c_orders;

UPDATE runner_ratings
	SET runner_id = r.runner_id
	FROM r_orders AS r
	WHERE runner_ratings.order_id = r.order_id;

UPDATE runner_ratings
	SET rating = floor(random() * 4 + 1)::int
	WHERE order_id IN (SELECT order_id FROM r_orders
		WHERE cancellation IS NULL);

SELECT * FROM runner_ratings ORDER BY order_id;

--4. Using your newly generated table - can you join all of the information together to form a table which has the following information for successful deliveries? customer_id, order_id, runner_id, rating, order_time, pickup_time, Time between order and pickup, Delivery duration, Average speed, Total number of pizzas
WITH counts AS (SELECT order_id, COUNT(*) AS count FROM c_orders GROUP BY order_id),
	times AS (SELECT DISTINCT order_id, order_time FROM c_orders)
SELECT ra.customer_id,
	co.order_id,
	ru.runner_id,
	ra.rating,
	ti.order_time,
	ru.pickup_time,
	ru.pickup_time - ti.order_time AS time_to_pickup,
	ru.duration AS duration_mins,
	ROUND(ru.distance::numeric / (ru.duration::numeric/60), 2) AS avg_speed_kmh, --divided by 60 to give km/h
	co.count AS pizzas_in_order 
FROM counts AS co
	LEFT JOIN times AS ti
	ON co.order_id = ti.order_id
	LEFT JOIN r_orders AS ru
	ON co.order_id = ru.order_id
	LEFT JOIN runner_ratings AS ra
	ON co.order_id = ra.order_id
WHERE co.order_id IN (SELECT order_id FROM r_orders WHERE cancellation IS NULL)
	ORDER BY order_id;


--If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras and each runner is paid $0.30 per kilometre traveled - how much money does Pizza Runner have left over after these deliveries?
WITH prices AS (SELECT order_id,
	SUM(price) AS price	
	FROM sales
	GROUP BY order_id),
	fees AS (SELECT order_id, distance::numeric * 0.30 AS fee FROM r_orders)
SELECT 
	ROUND(SUM(price - fee), 2) AS profit
	FROM prices AS p
	LEFT JOIN fees AS f
	ON p.order_id = f.order_id;



	
	