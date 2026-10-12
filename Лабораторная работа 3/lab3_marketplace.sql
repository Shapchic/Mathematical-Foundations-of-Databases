-- ====================================================================
-- Дисциплина: Базы данных / Математические основы баз данных
-- Лабораторная работа №3: Многотабличные запросы и аналитические представления
-- СУБД: PostgreSQL (версия 15+)
-- Клиент: pgAdmin 4 / psql
-- Сквозной кейс: База данных маркетплейса (Marketplace)
-- ====================================================================

-- --------------------------------------------------------------------
-- Задание 1: Запрос с внутренним соединением не менее трёх таблиц
-- Соединяемые таблицы: products (товары), categories (категории), sellers (продавцы), users (владельцы)
-- Назначение: Формирование товарной карточки с выводом наименования категории,
-- названия магазина продавца, ФИО владельца и текущей цены.
-- --------------------------------------------------------------------
SELECT 
    p.id        AS product_id,
    p.title     AS product_name,
    c.name      AS category_name,
    s.shop_name AS seller_store,
    u.full_name AS seller_owner,
    p.price     AS unit_price
FROM products p
INNER JOIN categories c ON c.id = p.category_id
INNER JOIN sellers s    ON s.id = p.seller_id
INNER JOIN users u      ON u.id = s.user_id
WHERE p.is_active = TRUE
ORDER BY p.price DESC
LIMIT 15;


-- --------------------------------------------------------------------
-- Задание 2: Запрос с LEFT JOIN, показывающий строки без соответствий (антисоединение)
-- Назначение: Выявление товаров, у которых ещё нет ни одного отзыва (reviews).
-- Маркетинговая цель: сформировать список товаров для промо-акции «Баллы за первый отзыв».
-- --------------------------------------------------------------------
SELECT 
    p.id        AS unreviewed_product_id,
    p.title     AS product_title,
    c.name      AS category_name,
    s.shop_name AS seller_name,
    p.price     AS price_rub
FROM products p
LEFT JOIN reviews r  ON r.product_id = p.id
INNER JOIN categories c ON c.id = p.category_id
INNER JOIN sellers s    ON s.id = p.seller_id
WHERE r.id IS NULL
ORDER BY p.id ASC
LIMIT 15;


-- --------------------------------------------------------------------
-- Задание 3: Запрос с группировкой и агрегацией
-- Назначение: Аналитика каталога товаров по категориям:
-- вычисление общего количества активных товаров, средней цены, минимальной и максимальной цены,
-- а также суммарного складского остатка.
-- --------------------------------------------------------------------
SELECT 
    c.id                   AS category_id,
    c.name                 AS category_name,
    COUNT(p.id)            AS active_products_count,
    ROUND(AVG(p.price), 2) AS avg_price_rub,
    MIN(p.price)           AS min_price_rub,
    MAX(p.price)           AS max_price_rub,
    COALESCE(SUM(st.quantity), 0) AS total_units_in_stock
FROM categories c
LEFT JOIN products p ON p.category_id = c.id AND p.is_active = TRUE
LEFT JOIN stock st   ON st.product_id = p.id
GROUP BY c.id, c.name
ORDER BY active_products_count DESC, c.name ASC;


-- --------------------------------------------------------------------
-- Задание 4: Применение HAVING для фильтрации групп
-- Назначение: Финансовый мониторинг успешных продавцов: отбор магазинов,
-- чья подтвержденная выручка по доставленным/отправленным заказам превысила 2 000 000 руб.
-- --------------------------------------------------------------------
SELECT 
    s.id                                       AS seller_id,
    s.shop_name                                AS store_title,
    COUNT(DISTINCT o.id)                       AS completed_orders_count,
    SUM(oi.quantity)                           AS total_units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price), 2) AS total_revenue_rub
FROM sellers s
INNER JOIN products p   ON p.seller_id = s.id
INNER JOIN order_items oi ON oi.product_id = p.id
INNER JOIN orders o     ON o.id = oi.order_id
WHERE o.status IN ('delivered', 'shipped')
GROUP BY s.id, s.shop_name
HAVING SUM(oi.quantity * oi.unit_price) > 2000000.00
ORDER BY total_revenue_rub DESC;


-- --------------------------------------------------------------------
-- Задание 5: Подзапросы трёх видов
-- --------------------------------------------------------------------

-- 5.1. Скалярный подзапрос: товары, цена которых выше средней цены по всему каталогу
SELECT 
    p.id    AS product_id,
    p.title AS product_name,
    p.price AS current_price,
    ROUND((SELECT AVG(price) FROM products WHERE is_active = TRUE), 2) AS catalog_avg_price,
    ROUND(p.price - (SELECT AVG(price) FROM products WHERE is_active = TRUE), 2) AS price_delta
FROM products p
WHERE p.is_active = TRUE
  AND p.price > (SELECT AVG(price) FROM products WHERE is_active = TRUE)
ORDER BY p.price DESC
LIMIT 10;

-- 5.2. Подзапрос с предикатом IN: заказы покупателей из Москвы и Санкт-Петербурга
SELECT 
    o.id           AS order_number,
    o.user_id      AS customer_id,
    o.status       AS order_status,
    o.total_amount AS total_sum_rub,
    o.created_at   AS order_date
FROM orders o
WHERE o.user_id IN (
    SELECT DISTINCT a.user_id 
    FROM addresses a 
    WHERE a.city IN ('Москва', 'Санкт-Петербург')
)
ORDER BY o.total_amount DESC
LIMIT 10;

-- 5.3. Коррелированный подзапрос с EXISTS: продавцы, имеющие товары с критическим остатком на складе (<= 3 шт.)
SELECT 
    s.id        AS seller_id,
    s.shop_name AS seller_store,
    s.description
FROM sellers s
WHERE EXISTS (
    SELECT 1 
    FROM products p
    INNER JOIN stock st ON st.product_id = p.id
    WHERE p.seller_id = s.id 
      AND st.quantity <= 3
)
ORDER BY s.id ASC;


-- --------------------------------------------------------------------
-- Задание 6: Общие табличные выражения (CTE)
-- --------------------------------------------------------------------

-- 6.1. Аналитический многошаговый CTE: расчёт выручки каждого продавца и его доли в общем обороте
WITH seller_sales AS (
    SELECT 
        p.seller_id,
        COUNT(DISTINCT oi.order_id) AS orders_count,
        SUM(oi.quantity * oi.unit_price) AS seller_revenue
    FROM products p
    INNER JOIN order_items oi ON oi.product_id = p.id
    GROUP BY p.seller_id
),
platform_totals AS (
    SELECT SUM(seller_revenue) AS total_platform_revenue
    FROM seller_sales
)
SELECT 
    s.shop_name                                                      AS "Магазин",
    ss.orders_count                                                  AS "Количество заказов",
    ROUND(ss.seller_revenue, 2)                                      AS "Выручка продавца (руб.)",
    ROUND((ss.seller_revenue / pt.total_platform_revenue) * 100, 2)  AS "Доля рынка (%)"
FROM seller_sales ss
INNER JOIN sellers s ON s.id = ss.seller_id
CROSS JOIN platform_totals pt
ORDER BY ss.seller_revenue DESC;

-- 6.2. Рекурсивный CTE (WITH RECURSIVE) для обхода иерархического дерева категорий
WITH RECURSIVE category_tree AS (
    -- Анкерная (стартовая) часть: выбор корневых категорий первого уровня
    SELECT 
        id,
        parent_id,
        name,
        1 AS level_depth,
        name::text AS full_hierarchy_path
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Рекурсивная часть: присоединение дочерних категорий
    SELECT 
        c.id,
        c.parent_id,
        c.name,
        ct.level_depth + 1,
        ct.full_hierarchy_path || ' -> ' || c.name
    FROM categories c
    INNER JOIN category_tree ct ON ct.id = c.parent_id
)
SELECT 
    id                  AS category_id,
    level_depth         AS "Уровень иерархии",
    full_hierarchy_path AS "Полный путь категории"
FROM category_tree
ORDER BY full_hierarchy_path ASC;


-- --------------------------------------------------------------------
-- Задание 7: Создание представлений (VIEW) для типовых аналитических отчётов
-- --------------------------------------------------------------------

-- 7.1. Представление 1: Витрина эффективности магазинов-продавцов
DROP VIEW IF EXISTS view_seller_performance;
CREATE VIEW view_seller_performance AS
SELECT 
    s.id                                              AS seller_id,
    s.shop_name                                       AS shop_name,
    u.full_name                                       AS owner_name,
    COUNT(DISTINCT p.id)                              AS total_products,
    COUNT(DISTINCT CASE WHEN p.is_active THEN p.id END) AS active_products,
    COALESCE(ROUND(AVG(r.rating), 2), 0.00)           AS average_rating,
    COALESCE(SUM(oi.quantity), 0)                     AS units_sold,
    COALESCE(ROUND(SUM(oi.quantity * oi.unit_price), 2), 0.00) AS total_revenue
FROM sellers s
INNER JOIN users u        ON u.id = s.user_id
LEFT JOIN products p      ON p.seller_id = s.id
LEFT JOIN reviews r       ON r.product_id = p.id
LEFT JOIN order_items oi  ON oi.product_id = p.id
GROUP BY s.id, s.shop_name, u.full_name;

-- 7.2. Представление 2: Витрина товарной и складской аналитики категорий
DROP VIEW IF EXISTS view_category_summary;
CREATE VIEW view_category_summary AS
SELECT 
    c.id                                     AS category_id,
    c.name                                   AS category_name,
    COUNT(p.id)                              AS total_products,
    ROUND(AVG(p.price), 2)                   AS avg_price,
    MIN(p.price)                             AS min_price,
    MAX(p.price)                             AS max_price,
    COALESCE(SUM(st.quantity), 0)            AS stock_balance
FROM categories c
LEFT JOIN products p ON p.category_id = c.id
LEFT JOIN stock st   ON st.product_id = p.id
GROUP BY c.id, c.name;

-- Демонстрация обращений к созданным представлениям:
-- Выборка топ-5 продавцов по выручке из view_seller_performance
SELECT * FROM view_seller_performance 
ORDER BY total_revenue DESC 
LIMIT 5;

-- Выборка категорий с наибольшим количеством складских остатков из view_category_summary
SELECT * FROM view_category_summary 
ORDER BY stock_balance DESC 
LIMIT 5;
