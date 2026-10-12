-- ====================================================================
-- Дисциплина: Базы данных / Математические основы баз данных
-- Лабораторная работа №2: Базовые SQL-запросы и фильтрация данных
-- СУБД: PostgreSQL (версия 15+)
-- Клиент: pgAdmin 4 / psql
-- Сквозной кейс: База данных маркетплейса (Marketplace)
-- ====================================================================

-- --------------------------------------------------------------------
-- ЧАСТЬ 1. НАПОЛНЕНИЕ ТАБЛИЦ ТЕСТОВЫМИ СОГЛАСОВАННЫМИ ДАННЫМИ
-- Согласно ТЗ: в крупные таблицы (товары, заказы) вносится не менее 1000 строк.
-- Очистка существующих данных перед наполнением (для повторного запуска):
-- --------------------------------------------------------------------

TRUNCATE TABLE deliveries, addresses, reviews, payments, 
               order_items, orders, cart_items, carts, 
               stock, products, categories, sellers, users 
RESTART IDENTITY CASCADE;

-- 1.1. Наполнение таблицы категорий (categories) с иерархией (parent_id)
-- Сначала корневые категории (parent_id = NULL)
INSERT INTO categories (name, parent_id) VALUES
('Электроника', NULL),
('Бытовая техника', NULL),
('Одежда и обувь', NULL),
('Книги', NULL),
('Дом и сад', NULL);

-- Затем подкатегории (ссылаются на id корневых)
INSERT INTO categories (name, parent_id) VALUES
('Смартфоны', 1),
('Ноутбуки и ПК', 1),
('Наушники и аудио', 1),
('Гаджеты и аксессуары', 1),
('Крупная бытовая техника', 2),
('Мелкая кухонная техника', 2),
('Климатическая техника', 2),
('Мужская одежда', 3),
('Женская одежда', 3),
('Спортивная обувь', 3),
('Художественная литература', 4),
('Учебная и профессиональная литература', 4),
('Детские книги', 4),
('Мебель и интерьер', 5),
('Садовая техника и инструмент', 5);

-- 1.2. Наполнение пользователей (users) — 100 записей
INSERT INTO users (full_name, email, phone, password_hash, role, created_at)
SELECT
    CASE (g % 10)
        WHEN 0 THEN 'Александр Иванов'
        WHEN 1 THEN 'Елена Смирнова'
        WHEN 2 THEN 'Дмитрий Кузнецов'
        WHEN 3 THEN 'Ольга Попова'
        WHEN 4 THEN 'Максим Васильев'
        WHEN 5 THEN 'Анна Соколова'
        WHEN 6 THEN 'Сергей Михайлов'
        WHEN 7 THEN 'Татьяна Новикова'
        WHEN 8 THEN 'Иван Федоров'
        ELSE 'Мария Морозова'
    END || ' #' || g AS full_name,
    'user_' || g || '@marketplace-study.ru' AS email,
    '+79' || LPAD((100000000 + g * 37)::text, 9, '0') AS phone,
    md5('pass_hash_' || g) AS password_hash,
    CASE WHEN g <= 20 THEN 'seller' ELSE 'customer' END AS role,
    NOW() - (g || ' days')::interval AS created_at
FROM generate_series(1, 100) AS g;

-- 1.3. Наполнение продавцов (sellers) — 20 магазинов
INSERT INTO sellers (user_id, shop_name, description, created_at)
SELECT
    g AS user_id,
    CASE (g % 5)
        WHEN 0 THEN 'ТехноМир Ритейл'
        WHEN 1 THEN 'Уютный Дом Электроникс'
        WHEN 2 THEN 'Модный Стиль Маркет'
        WHEN 3 THEN 'Книжный Лабиринт Знаний'
        ELSE 'МегаМаркет Дискаунтер'
    END || ' №' || g AS shop_name,
    'Официальный сертифицированный партнер маркетплейса с гарантией качества и быстрой доставкой №' || g AS description,
    NOW() - ((g + 20) || ' days')::interval AS created_at
FROM generate_series(1, 20) AS g;

-- 1.4. Наполнение адресов доставки (addresses) — 120 адресов
INSERT INTO addresses (user_id, city, street, house, apartment)
SELECT
    ((g % 100) + 1) AS user_id,
    CASE (g % 6)
        WHEN 0 THEN 'Москва'
        WHEN 1 THEN 'Санкт-Петербург'
        WHEN 2 THEN 'Новосибирск'
        WHEN 3 THEN 'Екатеринбург'
        WHEN 4 THEN 'Казань'
        ELSE 'Нижний Новгород'
    END AS city,
    CASE (g % 5)
        WHEN 0 THEN 'ул. Ленина'
        WHEN 1 THEN 'пр. Мира'
        WHEN 2 THEN 'ул. Гагарина'
        WHEN 3 THEN 'ул. Пушкина'
        ELSE 'Московский проспект'
    END AS street,
    (1 + (g % 90))::varchar AS house,
    (1 + (g % 200))::varchar AS apartment
FROM generate_series(1, 120) AS g;

-- 1.5. Наполнение товаров (products) — 1200 записей (>1000 по ТЗ!)
-- Используем генерацию названий в зависимости от подкатегорий (id от 6 до 20)
INSERT INTO products (seller_id, category_id, title, description, price, is_active, created_at)
SELECT
    ((g % 20) + 1) AS seller_id,
    6 + (g % 15) AS category_id,
    CASE (6 + (g % 15))
        WHEN 6 THEN 'Смартфон ' || (ARRAY['Galaxy Ultra', 'Pro Max', 'Redmi Note', 'Pixel Pro', 'Honor Magic'])[1 + (g % 5)] || ' Gen ' || g
        WHEN 7 THEN 'Ноутбук ' || (ARRAY['ThinkPad X', 'MacBook Air Style', 'ZenBook Pro', 'Legion Gaming', 'MateBook D'])[1 + (g % 5)] || ' #' || g
        WHEN 8 THEN 'Беспроводные наушники ' || (ARRAY['AirSound Pro', 'BassBoost Bass', 'NoiseCancel 300', 'StudioPods', 'SportFit'])[1 + (g % 5)] || ' v' || g
        WHEN 9 THEN 'Зарядная станция и чехол ' || (ARRAY['MagFast Armor', 'Slim Matte', 'PowerBank 20k', 'Glass Shield', 'Smart Cable'])[1 + (g % 5)] || ' #' || g
        WHEN 10 THEN 'Двухкамерный холодильник NoFrost ' || (ARRAY['FrostFree 400', 'CoolMaster Pro', 'EcoCold Duo', 'Nordic Ice', 'SmartCool'])[1 + (g % 5)] || ' ' || g
        WHEN 11 THEN 'Индукционная микроволновая печь ' || (ARRAY['WaveMaster Solo', 'ChefGrill Express', 'BakePro Smart', 'RapidWarm', 'CookEasy'])[1 + (g % 5)] || ' ' || g
        WHEN 12 THEN 'Сплит-система инверторная ' || (ARRAY['ClimateComfort 09', 'AirBreeze Inverter', 'SilentCool Pro', 'PolarAir 12', 'PureEco Eco'])[1 + (g % 5)] || ' ' || g
        WHEN 13 THEN 'Куртка мужская демисезонная ' || (ARRAY['Urban Windproof', 'Nordic Parka', 'Classic Trench', 'Active Softshell', 'Casual Bomber'])[1 + (g % 5)] || ' мод.' || g
        WHEN 14 THEN 'Платье вечернее элегантное ' || (ARRAY['Silk Touch', 'Cocktail Velvet', 'Summer Floral', 'Office Chic', 'Maxi Elegance'])[1 + (g % 5)] || ' мод.' || g
        WHEN 15 THEN 'Кроссовки беговые амортизирующие ' || (ARRAY['AirRun Pro', 'UltraBoost Step', 'TrailGrip Fast', 'SpeedMarathon', 'CityLight Sport'])[1 + (g % 5)] || ' р.' || (38 + (g % 8))
        WHEN 16 THEN 'Роман: ' || (ARRAY['Тайна забытого города', 'Звёздный странник', 'Тени прошлого', 'В лабиринте времени', 'Хроники севера'])[1 + (g % 5)] || '. Том ' || ((g % 5) + 1)
        WHEN 17 THEN 'Руководство: ' || (ARRAY['Базы данных PostgreSQL от А до Я', 'Архитектура микросервисов', 'Проектирование SQL систем', 'Алгоритмы и структуры данных', 'DevOps практики'])[1 + (g % 5)]
        WHEN 18 THEN 'Энциклопедия для школьников: ' || (ARRAY['Тайны вселенной', 'Великие открытия', 'Мир динозавров', 'Анатомия человека', 'Техника будущего'])[1 + (g % 5)]
        WHEN 19 THEN 'Ортопедическое компьютерное кресло ' || (ARRAY['ErgoPro Mesh', 'Gaming Throne', 'ComfortLeader', 'OfficeMaster Soft', 'Executive Leather'])[1 + (g % 5)] || ' ' || g
        ELSE 'Аккумуляторная газонокосилка ' || (ARRAY['GreenCut 36V', 'EcoMower Power', 'GardenPro Turbo', 'RobotLawn Smart', 'GrassMaster 40'])[1 + (g % 5)] || ' мод.' || g
    END AS title,
    -- Около 15% товаров оставляем с NULL в описании для проверки предикатов IS NULL
    CASE 
        WHEN (g % 7 = 0) THEN NULL 
        ELSE 'Высококачественный оригинальный товар с гарантией производителя. Прекрасно подходит для повседневного использования и профессиональных задач. Артикул изделия: ART-' || (100000 + g)
    END AS description,
    -- Вариативная цена в зависимости от категории
    ROUND((500.00 + ((g * 137) % 85000) + ((g % 9) * 250.50))::numeric, 2) AS price,
    -- 95% активных товаров, 5% неактивных
    (g % 20 != 0) AS is_active,
    NOW() - ((g % 180) || ' days')::interval AS created_at
FROM generate_series(1, 1200) AS g;

-- 1.6. Наполнение складских остатков (stock) — 1200 записей
INSERT INTO stock (product_id, quantity, updated_at)
SELECT
    g AS product_id,
    -- Часть товаров с нулевым остатком, часть с большим запасом
    CASE 
        WHEN g % 15 = 0 THEN 0
        ELSE ((g * 19) % 250) + 1
    END AS quantity,
    NOW() - ((g % 30) || ' days')::interval AS updated_at
FROM generate_series(1, 1200) AS g;

-- 1.7. Наполнение корзин и их позиций (carts, cart_items)
INSERT INTO carts (user_id, created_at)
SELECT
    g AS user_id,
    NOW() - (g || ' days')::interval AS created_at
FROM generate_series(1, 50) AS g;

INSERT INTO cart_items (cart_id, product_id, quantity)
SELECT
    ((g % 50) + 1) AS cart_id,
    ((g * 7) % 1200) + 1 AS product_id,
    ((g % 4) + 1) AS quantity
FROM generate_series(1, 120) AS g;

-- 1.8. Наполнение заказов (orders) — 1500 заказов (>1000 по ТЗ!)
INSERT INTO orders (user_id, status, total_amount, created_at)
SELECT
    ((g % 100) + 1) AS user_id,
    (ARRAY['created', 'processing', 'shipped', 'delivered', 'cancelled'])[1 + (g % 5)] AS status,
    0.00 AS total_amount, -- пересчитаем после заполнения позиций
    NOW() - ((g % 90) || ' days')::interval - ((g % 24) || ' hours')::interval AS created_at
FROM generate_series(1, 1500) AS g;

-- 1.9. Наполнение позиций заказов (order_items) — 3500 позиций
-- Каждый заказ связывается с товарами и фиксирует unit_price из products
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    sub.order_id,
    sub.product_id,
    sub.qty,
    p.price
FROM (
    SELECT
        g AS order_id,
        ((g * 13) % 1200) + 1 AS product_id,
        ((g % 3) + 1) AS qty
    FROM generate_series(1, 1500) AS g
    UNION
    SELECT
        g AS order_id,
        ((g * 29 + 5) % 1200) + 1 AS product_id,
        ((g % 2) + 1) AS qty
    FROM generate_series(1, 1200) AS g
    UNION
    SELECT
        g AS order_id,
        ((g * 47 + 11) % 1200) + 1 AS product_id,
        1 AS qty
    FROM generate_series(1, 800) AS g
) sub
JOIN products p ON p.id = sub.product_id
ON CONFLICT (order_id, product_id) DO NOTHING;

-- Обновление общей суммы заказа (total_amount) в orders
UPDATE orders o
SET total_amount = sub.sum_amt
FROM (
    SELECT order_id, SUM(quantity * unit_price) AS sum_amt
    FROM order_items
    GROUP BY order_id
) sub
WHERE o.id = sub.order_id;

-- 1.10. Наполнение платежей (payments) — 1500 записей
INSERT INTO payments (order_id, amount, payment_status, paid_at)
SELECT
    o.id AS order_id,
    o.total_amount AS amount,
    CASE o.status
        WHEN 'delivered' THEN 'completed'
        WHEN 'shipped'   THEN 'completed'
        WHEN 'cancelled' THEN 'failed'
        ELSE 'waiting'
    END AS payment_status,
    CASE 
        WHEN o.status IN ('delivered', 'shipped') THEN o.created_at + interval '10 minutes'
        ELSE NULL
    END AS paid_at
FROM orders o;

-- 1.11. Наполнение отзывов (reviews) — 800 записей
-- Около 400 товаров останутся БЕЗ отзывов (важно для демонстрации LEFT JOIN в Лабе 3!)
INSERT INTO reviews (user_id, product_id, rating, comment, created_at)
SELECT
    ((g % 100) + 1) AS user_id,
    g AS product_id,
    ((g % 5) + 1) AS rating,
    CASE ((g % 5) + 1)
        WHEN 5 THEN 'Великолепное качество! Полностью соответствует описанию, покупкой доволен на 100%.'
        WHEN 4 THEN 'Хороший товар за свою цену, доставили вовремя, комплектация полная.'
        WHEN 3 THEN 'Нормально, но упаковка была немного помята при транспортировке.'
        WHEN 2 THEN 'Качество среднее, ожидал большего от данного бренда.'
        ELSE 'Не понравилось качество сборки, оформил заявку на возврат.'
    END AS comment,
    NOW() - ((g % 60) || ' days')::interval AS created_at
FROM generate_series(1, 800) AS g;

-- 1.12. Наполнение доставок (deliveries) — 1500 доставок
INSERT INTO deliveries (order_id, address_id, delivery_status, delivery_date)
SELECT
    o.id AS order_id,
    ((o.id % 120) + 1) AS address_id,
    CASE o.status
        WHEN 'delivered' THEN 'delivered'
        WHEN 'shipped'   THEN 'in_transit'
        WHEN 'cancelled' THEN 'cancelled'
        ELSE 'created'
    END AS delivery_status,
    CASE 
        WHEN o.status = 'delivered' THEN o.created_at + interval '3 days'
        ELSE NULL
    END AS delivery_date
FROM orders o;

-- --------------------------------------------------------------------
-- ПРОВЕРКА ОБЪЕМОВ НАПОЛНЕНИЯ БАЗЫ ДАННЫХ
-- --------------------------------------------------------------------
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM users
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'categories', COUNT(*) FROM categories
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'stock', COUNT(*) FROM stock
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'addresses', COUNT(*) FROM addresses
UNION ALL
SELECT 'deliveries', COUNT(*) FROM deliveries;


-- ====================================================================
-- ЧАСТЬ 2. ВЫПОЛНЕНИЕ ТЕХНИЧЕСКОГО ЗАДАНИЯ ЛАБОРАТОРНОЙ РАБОТЫ №2
-- ====================================================================

-- --------------------------------------------------------------------
-- Задание 2: Запрос, выводящий заданные столбцы товаров без дубликатов (DISTINCT),
-- с осмысленными псевдонимами столбцов.
-- Назначение: Формирование каталога уникальных ценовых сегментов и признака
-- доступности по категориям товаров для построения аналитических срезов.
-- --------------------------------------------------------------------
SELECT DISTINCT
    category_id AS "Код категории",
    is_active   AS "Статус доступности (в продаже)",
    CASE 
        WHEN price < 5000.00 THEN 'Бюджетный сегмент (до 5 тыс.)'
        WHEN price BETWEEN 5000.00 AND 30000.00 THEN 'Средний сегмент (5 - 30 тыс.)'
        ELSE 'Премиум сегмент (свыше 30 тыс.)'
    END AS "Ценовой сегмент"
FROM products
ORDER BY "Код категории" ASC, "Ценовой сегмент" ASC;


-- --------------------------------------------------------------------
-- Задание 3: Запрос с фильтрацией по нескольким условиям,
-- объединённым AND и OR со скобками.
-- Назначение: Поиск целевых товаров для маркетинговой акции:
-- активные товары в категориях "Смартфоны" (6) и "Ноутбуки" (7) в диапазоне от 20000 до 60000 руб.,
-- ЛИБО товары категории "Наушники и аудио" (8) с ценой до 10000 руб.
-- --------------------------------------------------------------------
SELECT 
    id          AS product_id,
    title       AS product_name,
    category_id AS cat_id,
    price       AS original_price,
    ROUND(price * 0.90, 2) AS promo_price_10pct
FROM products
WHERE is_active = TRUE
  AND (
        (category_id IN (6, 7) AND price >= 20000.00 AND price <= 60000.00)
        OR 
        (category_id = 8 AND price <= 10000.00)
      )
ORDER BY original_price DESC;


-- --------------------------------------------------------------------
-- Задание 4: Применение предикатов BETWEEN, IN, LIKE (ILIKE) и IS NULL.
-- Каждое условие продемонстрировано как в точечном запросе, так и в едином комплексном фильтре.
-- --------------------------------------------------------------------

-- 4.1. Демонстрация BETWEEN: выборка заказов с суммой от 10000 до 50000 руб.
SELECT 
    id           AS order_number,
    user_id      AS customer_id,
    status       AS order_status,
    total_amount AS total_sum
FROM orders
WHERE total_amount BETWEEN 10000.00 AND 50000.00
ORDER BY total_sum DESC;

-- 4.2. Демонстрация IN: выборка заказов в активной фазе выполнения
SELECT 
    id         AS order_number,
    status     AS current_stage,
    created_at AS order_timestamp
FROM orders
WHERE status IN ('processing', 'shipped')
ORDER BY order_timestamp DESC;

-- 4.3. Демонстрация ILIKE: регистронезависимый поиск товаров с ключевым словом 'pro' в названии
SELECT 
    id    AS product_id,
    title AS product_title,
    price AS unit_cost
FROM products
WHERE title ILIKE '%pro%'
ORDER BY price DESC;

-- 4.4. Демонстрация IS NULL: поиск товаров без заполненного описания (для модерации контента)
SELECT 
    id                          AS unmoderated_product_id,
    title                       AS product_title,
    category_id                 AS cat_id,
    COALESCE(description, '--- ОПИСАНИЕ НЕ ЗАПОЛНЕНО ---') AS moderated_description
FROM products
WHERE description IS NULL
ORDER BY id ASC;

-- 4.5. КОМПЛЕКСНЫЙ ЗАПРОС: одновременное применение BETWEEN, IN, ILIKE и IS NULL (или IS NOT NULL)
-- Назначение: Поиск качественных товаров с описанием в выбранных категориях,
-- с ценой в заданном коридоре и содержащих маркер модели в наименовании.
SELECT 
    id          AS item_id,
    category_id AS cat_id,
    title       AS item_title,
    price       AS item_price
FROM products
WHERE category_id IN (6, 7, 8, 9, 10)
  AND price BETWEEN 5000.00 AND 75000.00
  AND title ILIKE '%pro%'
  AND description IS NOT NULL
ORDER BY price ASC;


-- --------------------------------------------------------------------
-- Задание 5: Запрос с сортировкой по двум столбцам в разных направлениях.
-- Назначение: Группировка товаров по категории по возрастанию (ASC),
-- а внутри каждой категории — ранжирование от самых дорогих к дешёвым (DESC).
-- Также демонстрируется явное управление положением NULL (NULLS LAST).
-- --------------------------------------------------------------------
SELECT 
    category_id AS cat_id,
    id          AS prod_id,
    title       AS prod_name,
    price       AS prod_price,
    description AS prod_desc
FROM products
WHERE is_active = TRUE
ORDER BY category_id ASC, price DESC NULLS LAST;


-- --------------------------------------------------------------------
-- Задание 6: Реализация постраничного вывода (пагинации) с помощью LIMIT и OFFSET.
-- Назначение: Вывод 2-й и 3-й страниц каталога активных товаров при размере страницы 10 записей.
-- Обязательно применяется детерминированный ORDER BY id ASC во избежание дублирования строк.
-- --------------------------------------------------------------------

-- Первая страница (страница 1, 10 товаров)
SELECT 
    id          AS product_id,
    title       AS product_title,
    category_id AS cat_id,
    price       AS price_rub
FROM products
WHERE is_active = TRUE
ORDER BY id ASC
LIMIT 10 OFFSET 0;

-- Вторая страница (страница 2, следующие 10 товаров со смещением 10)
SELECT 
    id          AS product_id,
    title       AS product_title,
    category_id AS cat_id,
    price       AS price_rub
FROM products
WHERE is_active = TRUE
ORDER BY id ASC
LIMIT 10 OFFSET 10;

-- Третья страница (страница 3, смещение 20)
SELECT 
    id          AS product_id,
    title       AS product_title,
    category_id AS cat_id,
    price       AS price_rub
FROM products
WHERE is_active = TRUE
ORDER BY id ASC
LIMIT 10 OFFSET 20;

-- --------------------------------------------------------------------
-- Дополнительный аналитический запрос: DISTINCT ON (PostgreSQL specific)
-- Назначение: Вывод ровно одного самого дорогого товара для каждой категории
-- --------------------------------------------------------------------
SELECT DISTINCT ON (category_id)
    category_id AS cat_id,
    id          AS top_product_id,
    title       AS top_product_title,
    price       AS max_price
FROM products
WHERE is_active = TRUE
ORDER BY category_id ASC, price DESC;
