-- ====================================================================
-- Дисциплина: Базы данных / Математические основы баз данных
-- Лабораторная работа №4: Оконные функции и аналитика данных
-- СУБД: PostgreSQL (версия 15+)
-- Клиент: pgAdmin 4 / psql
-- Сквозной кейс: База данных маркетплейса (Marketplace)
-- ====================================================================

-- --------------------------------------------------------------------
-- Задание 1: Рейтинг товаров по цене внутри каждой категории с помощью
-- ROW_NUMBER(), RANK() и DENSE_RANK().
-- Назначение: Сравнительный анализ поведения трёх основных функций ранжирования
-- на строках товаров внутри разделов каталога.
-- --------------------------------------------------------------------
SELECT 
    c.name                                AS category_name,
    p.id                                  AS product_id,
    p.title                               AS product_name,
    p.price                               AS unit_price,
    ROW_NUMBER() OVER w                   AS row_num,
    RANK()       OVER w                   AS rank_pos,
    DENSE_RANK() OVER w                   AS dense_rank_pos
FROM products p
INNER JOIN categories c ON c.id = p.category_id
WHERE p.is_active = TRUE
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
ORDER BY p.category_id ASC, p.price DESC
LIMIT 20;


-- --------------------------------------------------------------------
-- Задание 2: Для каждой категории вывести три самых дорогих товара (Топ-3)
-- Назначение: Выделение флагманских товаров каждой категории через CTE и
-- оконную функцию ROW_NUMBER() с фильтрацией во внешнем запросе WHERE rn <= 3.
-- --------------------------------------------------------------------
WITH ranked_products AS (
    SELECT 
        c.name AS category_name,
        p.id AS product_id,
        p.title AS product_name,
        p.price AS product_price,
        ROW_NUMBER() OVER (
            PARTITION BY p.category_id 
            ORDER BY p.price DESC, p.id ASC
        ) AS price_rank
    FROM products p
    INNER JOIN categories c ON c.id = p.category_id
    WHERE p.is_active = TRUE
)
SELECT 
    category_name,
    price_rank        AS "Место в топе",
    product_id        AS "ID товара",
    product_name      AS "Наименование товара",
    product_price     AS "Цена (руб.)"
FROM ranked_products
WHERE price_rank <= 3
ORDER BY category_name ASC, price_rank ASC;


-- --------------------------------------------------------------------
-- Задание 3: Нарастающий итог выручки по дням оконной агрегатной функцией
-- Назначение: Финансовый анализ кумулятивной выручки маркетплейса с течением времени.
-- Используется конструкция SUM(...) OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW).
-- --------------------------------------------------------------------
WITH daily_sales AS (
    SELECT 
        o.created_at::date               AS sales_date,
        COUNT(DISTINCT o.id)             AS orders_count,
        SUM(oi.quantity * oi.unit_price) AS daily_revenue
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status IN ('delivered', 'shipped')
    GROUP BY o.created_at::date
)
SELECT 
    sales_date                                                       AS "Дата продаж",
    orders_count                                                     AS "Число заказов",
    ROUND(daily_revenue, 2)                                          AS "Выручка за день (руб.)",
    ROUND(SUM(daily_revenue) OVER (
        ORDER BY sales_date 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                                            AS "Кумулятивная выручка (руб.)"
FROM daily_sales
ORDER BY sales_date ASC
LIMIT 15;


-- --------------------------------------------------------------------
-- Задание 4: Доля выручки каждого продавца в выручке его категории
-- Назначение: Определение монополизации и структуры продаж внутри разделов каталога
-- с использованием SUM(...) OVER (PARTITION BY category_id).
-- --------------------------------------------------------------------
WITH seller_cat_revenue AS (
    SELECT 
        p.category_id,
        c.name AS category_name,
        s.id AS seller_id,
        s.shop_name,
        SUM(oi.quantity * oi.unit_price) AS seller_category_revenue
    FROM products p
    INNER JOIN categories c ON c.id = p.category_id
    INNER JOIN sellers s    ON s.id = p.seller_id
    INNER JOIN order_items oi ON oi.product_id = p.id
    INNER JOIN orders o       ON o.id = oi.order_id
    WHERE o.status IN ('delivered', 'shipped')
    GROUP BY p.category_id, c.name, s.id, s.shop_name
)
SELECT 
    category_name                                               AS "Категория",
    shop_name                                                   AS "Магазин продавца",
    ROUND(seller_category_revenue, 2)                           AS "Выручка продавца (руб.)",
    ROUND(SUM(seller_category_revenue) OVER (
        PARTITION BY category_id
    ), 2)                                                       AS "Общая выручка категории (руб.)",
    ROUND((seller_category_revenue / SUM(seller_category_revenue) OVER (
        PARTITION BY category_id
    )) * 100, 2)                                                AS "Доля продавца в категории (%)"
FROM seller_cat_revenue
ORDER BY category_name ASC, "Доля продавца в категории (%)" DESC
LIMIT 20;


-- --------------------------------------------------------------------
-- Задание 5: Применение LAG и LEAD для сравнения выручки текущего дня с предыдущим
-- Назначение: Мониторинг ежедневной динамики выручки: определение абсолютного прироста
-- и относительного темпа роста к предыдущему периоду.
-- --------------------------------------------------------------------
WITH daily_summary AS (
    SELECT 
        o.created_at::date AS order_day,
        ROUND(SUM(oi.quantity * oi.unit_price), 2) AS today_revenue
    FROM orders o
    INNER JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status IN ('delivered', 'shipped')
    GROUP BY o.created_at::date
)
SELECT 
    order_day                                                       AS "Дата",
    today_revenue                                                   AS "Выручка сегодня (руб.)",
    LAG(today_revenue, 1) OVER (ORDER BY order_day)                 AS "Выручка вчера (LAG)",
    LEAD(today_revenue, 1) OVER (ORDER BY order_day)                AS "Выручка завтра (LEAD)",
    ROUND(today_revenue - LAG(today_revenue, 1) OVER (ORDER BY order_day), 2) 
                                                                    AS "Абсолютный прирост (руб.)",
    ROUND(
        ((today_revenue - LAG(today_revenue, 1) OVER (ORDER BY order_day)) / 
        NULLIF(LAG(today_revenue, 1) OVER (ORDER BY order_day), 0)) * 100, 
        2
    )                                                               AS "Темп прироста (%)"
FROM daily_summary
ORDER BY order_day ASC
LIMIT 15;


-- --------------------------------------------------------------------
-- Задание 6: Решение одной аналитической задачи двумя способами:
-- Способ 1: Оконная функция
-- Способ 2: Классическая группировка с JOIN подзапроса
-- Задача: Вывести детальные данные каждого товара вместе со средней ценой
-- по его категории и отклонением цены товара от средней.
-- --------------------------------------------------------------------

-- Способ 6.1: Оконная функция AVG(...) OVER (PARTITION BY category_id)
SELECT 
    p.id                                                               AS product_id,
    p.category_id                                                      AS cat_id,
    p.title                                                            AS product_title,
    p.price                                                            AS product_price,
    ROUND(AVG(p.price) OVER (PARTITION BY p.category_id), 2)           AS category_avg_price,
    ROUND(p.price - AVG(p.price) OVER (PARTITION BY p.category_id), 2) AS price_delta
FROM products p
WHERE p.is_active = TRUE
ORDER BY p.category_id ASC, p.price DESC
LIMIT 10;

-- Способ 6.2: Классическая группировка через GROUP BY и INNER JOIN
SELECT 
    p.id                                    AS product_id,
    p.category_id                           AS cat_id,
    p.title                                 AS product_title,
    p.price                                 AS product_price,
    ROUND(cat_stats.avg_price, 2)           AS category_avg_price,
    ROUND(p.price - cat_stats.avg_price, 2) AS price_delta
FROM products p
INNER JOIN (
    SELECT 
        category_id, 
        AVG(price) AS avg_price
    FROM products
    WHERE is_active = TRUE
    GROUP BY category_id
) cat_stats ON cat_stats.category_id = p.category_id
WHERE p.is_active = TRUE
ORDER BY p.category_id ASC, p.price DESC
LIMIT 10;
