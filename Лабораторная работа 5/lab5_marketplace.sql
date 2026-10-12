-- ====================================================================
-- Дисциплина: Базы данных / Математические основы баз данных
-- Лабораторная работа №5: Транзакции, целостность данных и серверная логика
-- СУБД: PostgreSQL (версия 15+)
-- Клиент: pgAdmin 4 / psql
-- Сквозной кейс: База данных маркетплейса (Marketplace)
-- ====================================================================

-- --------------------------------------------------------------------
-- ЧАСТЬ 1. ДЕМОНСТРАЦИЯ РАБОТЫ ТРАНЗАКЦИЙ (BEGIN, COMMIT, ROLLBACK, SAVEPOINT)
-- --------------------------------------------------------------------

-- 1.1. Успешный сценарий транзакции (BEGIN ... COMMIT)
-- Задача: Согласованно создать заказ, добавить позицию и уменьшить остаток товара
BEGIN;

-- Шаг 1: Создание заказа пользователя 42
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (42, 'processing', 15000.00, NOW());

-- Шаг 2: Добавление позиции заказа (товар ID=10, 2 шт. по цене 7500.00)
-- Используем последний сгенерированный id заказа через курсор subquery
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES ((SELECT MAX(id) FROM orders WHERE user_id = 42), 10, 2, 7500.00);

-- Шаг 3: Синхронное списание остатка со склада
UPDATE stock 
SET quantity = quantity - 2, updated_at = NOW() 
WHERE product_id = 10;

-- Фиксация изменений: все действия становятся постоянными и атомарными
COMMIT;

-- Проверка результата успешной транзакции
SELECT * FROM stock WHERE product_id = 10;
SELECT * FROM orders WHERE user_id = 42 ORDER BY id DESC LIMIT 1;


-- 1.2. Сценарий с намеренной ошибкой и откатом (ROLLBACK)
-- Задача: Показать, что при возникновении сбоя (нарушение CHECK-ограничения)
-- ни одно из промежуточных действий не остаётся в базе данных.
BEGIN;

-- Создаем заказ
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (42, 'created', 50000.00, NOW());

-- Намеренная ошибка: вставляем недопустимое отрицательное количество товара (-5 шт.),
-- что нарушает ограничение quantity_order_positive CHECK (quantity > 0)
-- При выполнении этого шага PostgreSQL сгенерирует ошибку и переведет транзакцию в состояние ABORTED
DO $$
BEGIN
    BEGIN
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES ((SELECT MAX(id) FROM orders WHERE user_id = 42), 10, -5, 10000.00);
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'Перехвачена ожидаемая ошибка CHECK-ограничения: отрицательное количество!';
    END;
END $$;

-- Откатываем транзакцию: заказ НЕ будет создан
ROLLBACK;


-- 1.3. Демонстрация точек сохранения (SAVEPOINT)
BEGIN;

INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (43, 'processing', 20000.00, NOW());

SAVEPOINT order_created;

-- Попытка зарезервировать акционный подарок (с ошибочным товаром id=9999999)
DO $$
BEGIN
    BEGIN
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES ((SELECT MAX(id) FROM orders WHERE user_id = 43), 9999999, 1, 100.00);
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'Товар не найден, откатываемся к точке сохранения savepoint!';
    END;
END $$;

ROLLBACK TO SAVEPOINT order_created;

-- Фиксируем только основной заказ без ошибочного подарка
COMMIT;


-- --------------------------------------------------------------------
-- ЧАСТЬ 2. ФУНКЦИЯ НА PL/pgSQL ДЛЯ АТОМАРНОГО ОФОРМЛЕНИЯ ЗАКАЗА
-- Назначение: Проверка активности товара, блокировка остатка FOR UPDATE,
-- валидация остатка, создание заказа, добавление позиции, уменьшение остатка.
-- При нехватке товара возбуждается исключение RAISE EXCEPTION.
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION place_order(
    p_user_id BIGINT,
    p_product_id BIGINT,
    p_quantity INT
)
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_unit_price NUMERIC(12,2);
    v_current_stock INT;
    v_is_active BOOLEAN;
BEGIN
    -- 1. Проверка корректности параметров
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Запрашиваемое количество товара должно быть больше 0 (передано: %)', p_quantity;
    END IF;

    -- 2. Получение цены и статуса активности товара
    SELECT price, is_active 
    INTO v_unit_price, v_is_active 
    FROM products 
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар с идентификатором ID=% не найден в каталоге', p_product_id;
    END IF;

    IF NOT v_is_active THEN
        RAISE EXCEPTION 'Товар с ID=% в данный момент не активен для заказа', p_product_id;
    END IF;

    -- 3. Блокировка строки остатка на складе (защита от состояния гонки при конкурентных заказах)
    SELECT quantity 
    INTO v_current_stock 
    FROM stock 
    WHERE product_id = p_product_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Складская запись для товара ID=% отсутствует', p_product_id;
    END IF;

    -- 4. Проверка достаточности складского остатка
    IF v_current_stock < p_quantity THEN
        RAISE EXCEPTION 'Недостаточно товара на складе (товар ID=%, в наличии=%, запрошено=%)', 
            p_product_id, v_current_stock, p_quantity;
    END IF;

    -- 5. Атомарное создание заказа
    INSERT INTO orders (user_id, status, total_amount, created_at)
    VALUES (p_user_id, 'processing', v_unit_price * p_quantity, NOW())
    RETURNING id INTO v_order_id;

    -- 6. Добавление позиции заказа
    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_quantity, v_unit_price);

    -- 7. Уменьшение складского остатка
    UPDATE stock 
    SET quantity = quantity - p_quantity, 
        updated_at = NOW() 
    WHERE product_id = p_product_id;

    -- 8. Возврат номера успешно созданного заказа
    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Демонстрация успешного вызова функции place_order
SELECT place_order(15, 25, 2) AS created_new_order_id;

-- Демонстрация обработки исключения при заказе свыше остатка (раскомментируйте для теста):
-- SELECT place_order(15, 25, 999999);


-- --------------------------------------------------------------------
-- ЧАСТЬ 3. ФУНКЦИЯ РАСЧЁТА СВОДНОГО ПОКАЗАТЕЛЯ (ВЫРУЧКА ПРОДАВЦА ЗА ПЕРИОД)
-- Назначение: Использование локальных переменных, агрегатных запросов SELECT ... INTO
-- и возврата сводной таблицы показателей эффективности.
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_seller_revenue(
    p_seller_id BIGINT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    seller_id BIGINT,
    shop_name VARCHAR(150),
    period_start DATE,
    period_end DATE,
    orders_count BIGINT,
    items_sold BIGINT,
    total_revenue NUMERIC(14,2)
) AS $$
DECLARE
    v_shop_name VARCHAR(150);
    v_orders_cnt BIGINT := 0;
    v_items_cnt BIGINT := 0;
    v_rev NUMERIC(14,2) := 0.00;
BEGIN
    -- Проверка существования продавца
    SELECT s.shop_name INTO v_shop_name FROM sellers s WHERE s.id = p_seller_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Продавец с идентификатором ID=% не существует', p_seller_id;
    END IF;

    -- Расчет показателей за указанный период
    SELECT 
        COUNT(DISTINCT o.id),
        COALESCE(SUM(oi.quantity), 0),
        COALESCE(SUM(oi.quantity * oi.unit_price), 0.00)
    INTO v_orders_cnt, v_items_cnt, v_rev
    FROM products p
    INNER JOIN order_items oi ON oi.product_id = p.id
    INNER JOIN orders o ON o.id = oi.order_id
    WHERE p.seller_id = p_seller_id
      AND o.status IN ('delivered', 'shipped')
      AND o.created_at::date BETWEEN p_start_date AND p_end_date;

    RETURN QUERY SELECT 
        p_seller_id, v_shop_name, p_start_date, p_end_date, 
        v_orders_cnt, v_items_cnt, v_rev;
END;
$$ LANGUAGE plpgsql;

-- Демонстрация работы функции get_seller_revenue
SELECT * FROM get_seller_revenue(1, CURRENT_DATE - INTERVAL '90 days', CURRENT_DATE);


-- --------------------------------------------------------------------
-- ЧАСТЬ 4. ТРИГГЕР АУДИТА ИЗМЕНЕНИЯ ЦЕНЫ ТОВАРА
-- Назначение: Автоматическая фиксация старой и новой цены, процента изменения,
-- автора и времени изменения в служебной таблице журнала аудита.
-- --------------------------------------------------------------------

-- Таблица журнала аудита цен
CREATE TABLE IF NOT EXISTS product_price_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price NUMERIC(12,2) NOT NULL,
    new_price NUMERIC(12,2) NOT NULL,
    price_change_pct NUMERIC(6,2),
    changed_by VARCHAR(100) DEFAULT CURRENT_USER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Функция триггера аудита
CREATE OR REPLACE FUNCTION audit_product_price_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Срабатываем только если цена действительно изменилась
    IF OLD.price IS DISTINCT FROM NEW.price THEN
        INSERT INTO product_price_audit (
            product_id,
            old_price,
            new_price,
            price_change_pct,
            changed_by,
            changed_at
        ) VALUES (
            OLD.id,
            OLD.price,
            NEW.price,
            ROUND(((NEW.price - OLD.price) / OLD.price) * 100, 2),
            CURRENT_USER,
            NOW()
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Создание триггера уровня строки
DROP TRIGGER IF EXISTS trg_audit_product_price ON products;
CREATE TRIGGER trg_audit_product_price
AFTER UPDATE OF price ON products
FOR EACH ROW
EXECUTE FUNCTION audit_product_price_change();

-- Демонстрация работы триггера аудита:
-- 1. Обновляем цену товара ID=10 (увеличиваем на 10%)
UPDATE products 
SET price = ROUND(price * 1.10, 2) 
WHERE id = 10;

-- 2. Проверяем журнал аудита
SELECT * FROM product_price_audit WHERE product_id = 10 ORDER BY id DESC;


-- --------------------------------------------------------------------
-- ЧАСТЬ 5. ТРИГГЕР ДЛЯ ПОДДЕРЖАНИЯ ДЕНОРМАЛИЗОВАННОГО ПОЛЯ (РЕЙТИНГ ТОВАРА)
-- Назначение: В таблице products добавляется столбец rating. При добавлении,
-- изменении или удалении отзыва триггер автоматически пересчитывает средний рейтинг.
-- --------------------------------------------------------------------

-- Добавление денормализованного поля рейтинга в products
ALTER TABLE products ADD COLUMN IF NOT EXISTS rating NUMERIC(3,2) DEFAULT 0.00;

-- Первичная инициализация рейтингов товаров из существующих отзывов
UPDATE products p
SET rating = COALESCE(sub.avg_score, 0.00)
FROM (
    SELECT product_id, ROUND(AVG(rating), 2) AS avg_score
    FROM reviews
    GROUP BY product_id
) sub
WHERE p.id = sub.product_id;

-- Триггерная функция пересчёта рейтинга
CREATE OR REPLACE FUNCTION refresh_product_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_prod_id BIGINT;
    v_new_rating NUMERIC(3,2);
BEGIN
    -- Определяем ID товара в зависимости от типа операции (TG_OP)
    IF TG_OP = 'DELETE' THEN
        v_prod_id := OLD.product_id;
    ELSE
        v_prod_id := NEW.product_id;
    END IF;

    -- Пересчитываем средний рейтинг товара по всем отзывам
    SELECT COALESCE(ROUND(AVG(rating), 2), 0.00)
    INTO v_new_rating
    FROM reviews
    WHERE product_id = v_prod_id;

    -- Обновляем денормализованное поле в карточке товара
    UPDATE products
    SET rating = v_new_rating
    WHERE id = v_prod_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Создание триггера на таблицу reviews (INSERT, UPDATE, DELETE)
DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;
CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION refresh_product_rating();

-- Демонстрация работы триггера рейтинга:
-- Смотрим рейтинг товара ID=50 до вставки
SELECT id, title, rating FROM products WHERE id = 50;

-- Добавляем отличный отзыв с оценкой 5
INSERT INTO reviews (user_id, product_id, rating, comment, created_at)
VALUES (1, 50, 5, 'Потрясающий товар, ставлю твердую пятерку!', NOW());

-- Проверяем, что рейтинг товара ID=50 автоматически пересчитался
SELECT id, title, rating FROM products WHERE id = 50;
