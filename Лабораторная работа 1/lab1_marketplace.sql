-- ====================================================================
-- Дисциплина: Базы данных / Математические основы баз данных
-- Лабораторная работа №1: Проектирование и создание структуры базы данных
-- СУБД: PostgreSQL (версия 15+)
-- Клиент: pgAdmin 4 / psql
-- Сквозной кейс: База данных маркетплейса (Marketplace)
-- ====================================================================

-- --------------------------------------------------------------------
-- Очистка существующих таблиц схемы (для возможности повторного запуска)
-- Удаление производится в порядке, обратном зависимостям внешних ключей.
-- --------------------------------------------------------------------

DROP TABLE IF EXISTS deliveries CASCADE;
DROP TABLE IF EXISTS addresses CASCADE;
DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS carts CASCADE;
DROP TABLE IF EXISTS stock CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ====================================================================
-- 1. Таблица: users (Пользователи маркетплейса)
-- Сущность: Учётные записи покупателей, продавцов и администраторов
-- ====================================================================
CREATE TABLE users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'customer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_user_email UNIQUE (email),
    CONSTRAINT chk_user_role CHECK (role IN ('customer', 'seller', 'admin'))
);

COMMENT ON TABLE users IS 'Учетные записи пользователей площадки (покупатели и владельцы магазинов)';
COMMENT ON COLUMN users.id IS 'Суррогатный первичный ключ пользователя';
COMMENT ON COLUMN users.full_name IS 'Полное имя (ФИО) пользователя';
COMMENT ON COLUMN users.email IS 'Уникальный адрес электронной почты (логин)';
COMMENT ON COLUMN users.phone IS 'Номер контактного телефона';
COMMENT ON COLUMN users.password_hash IS 'Хэш пароля для авторизации';
COMMENT ON COLUMN users.role IS 'Роль в системе: customer, seller или admin';
COMMENT ON COLUMN users.created_at IS 'Метка времени регистрации аккаунта';


-- ====================================================================
-- 2. Таблица: sellers (Продавцы / Магазины)
-- Связь: 1:1 к users (каждый продавец привязан к учетной записи владельца)
-- ====================================================================
CREATE TABLE sellers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    shop_name VARCHAR(150) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_seller_user UNIQUE (user_id),
    CONSTRAINT fk_seller_user FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE sellers IS 'Продавцы (магазины), размещающие товары на маркетплейсе';
COMMENT ON COLUMN sellers.id IS 'Суррогатный первичный ключ магазина';
COMMENT ON COLUMN sellers.user_id IS 'Внешний ключ на пользователя-владельца (связь 1:1)';
COMMENT ON COLUMN sellers.shop_name IS 'Официальное публичное наименование магазина';
COMMENT ON COLUMN sellers.description IS 'Описание магазина и условий сотрудничества';
COMMENT ON COLUMN sellers.created_at IS 'Дата и время открытия магазина';


-- ====================================================================
-- 3. Таблица: categories (Иерархический классификатор категорий)
-- Связь: Иерархическая самоссылка (parent_id -> categories.id)
-- ====================================================================
CREATE TABLE categories (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id BIGINT,
    name VARCHAR(100) NOT NULL,

    CONSTRAINT uq_category_name UNIQUE (name),
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_id)
        REFERENCES categories(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE categories IS 'Иерархический классификатор категорий товаров маркетплейса';
COMMENT ON COLUMN categories.id IS 'Суррогатный первичный ключ категории';
COMMENT ON COLUMN categories.parent_id IS 'Ссылка на родительскую категорию (NULL для корневых разделов)';
COMMENT ON COLUMN categories.name IS 'Уникальное название категории';


-- ====================================================================
-- 4. Таблица: products (Товары каталога)
-- Связи: 1:N от sellers (продавец) и 1:N от categories (категория)
-- ====================================================================
CREATE TABLE products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    price NUMERIC(12,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT price_positive CHECK (price > 0),
    CONSTRAINT fk_product_seller FOREIGN KEY (seller_id)
        REFERENCES sellers(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_product_category FOREIGN KEY (category_id)
        REFERENCES categories(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE products IS 'Карточки товаров, продаваемых на площадке';
COMMENT ON COLUMN products.id IS 'Суррогатный первичный ключ товара';
COMMENT ON COLUMN products.seller_id IS 'Ссылка на магазин продавца';
COMMENT ON COLUMN products.category_id IS 'Ссылка на категорию классификатора';
COMMENT ON COLUMN products.title IS 'Наименование товара';
COMMENT ON COLUMN products.description IS 'Подробное описание характеристик товара';
COMMENT ON COLUMN products.price IS 'Цена товара в рублях (NUMERIC для точности денег)';
COMMENT ON COLUMN products.is_active IS 'Флаг доступности товара к покупке';
COMMENT ON COLUMN products.created_at IS 'Дата добавления товара в каталог';


-- ====================================================================
-- 5. Таблица: stock (Складские остатки)
-- Связь: 1:1 к products (актуальный остаток по каждому товару)
-- ====================================================================
CREATE TABLE stock (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_stock_product UNIQUE (product_id),
    CONSTRAINT stock_positive CHECK (quantity >= 0),
    CONSTRAINT fk_stock_product FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE stock IS 'Актуальные складские остатки товаров на складах площадки';
COMMENT ON COLUMN stock.id IS 'Суррогатный первичный ключ складской записи';
COMMENT ON COLUMN stock.product_id IS 'Ссылка на соответствующий товар';
COMMENT ON COLUMN stock.quantity IS 'Количество единиц товара в наличии (неотрицательное число)';
COMMENT ON COLUMN stock.updated_at IS 'Метка времени последнего изменения остатка';


-- ====================================================================
-- 6. Таблица: carts (Корзины покупателей)
-- Связь: 1:1 к users (у покупателя одна активная корзина)
-- ====================================================================
CREATE TABLE carts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_cart_user UNIQUE (user_id),
    CONSTRAINT fk_cart_user FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE carts IS 'Покупательские корзины для отложенных товаров';
COMMENT ON COLUMN carts.id IS 'Суррогатный первичный ключ корзины';
COMMENT ON COLUMN carts.user_id IS 'Ссылка на пользователя-владельца корзины';
COMMENT ON COLUMN carts.created_at IS 'Дата создания корзины';


-- ====================================================================
-- 7. Таблица: cart_items (Позиции корзины)
-- Связь: M:N между carts и products
-- ====================================================================
CREATE TABLE cart_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,

    CONSTRAINT quantity_positive CHECK (quantity > 0),
    CONSTRAINT uq_cart_product UNIQUE (cart_id, product_id),
    CONSTRAINT fk_cart_item_cart FOREIGN KEY (cart_id)
        REFERENCES carts(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_cart_item_product FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE cart_items IS 'Товары, помещенные пользователем в корзину';
COMMENT ON COLUMN cart_items.id IS 'Суррогатный первичный ключ позиции корзины';
COMMENT ON COLUMN cart_items.cart_id IS 'Ссылка на корзину';
COMMENT ON COLUMN cart_items.product_id IS 'Ссылка на отложенный товар';
COMMENT ON COLUMN cart_items.quantity IS 'Количество единиц товара в корзине (> 0)';


-- ====================================================================
-- 8. Таблица: orders (Оформленные заказы)
-- Связь: 1:N от users (покупатель)
-- ====================================================================
CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status VARCHAR(30) DEFAULT 'created',
    total_amount NUMERIC(12,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT total_amount_positive CHECK (total_amount >= 0),
    CONSTRAINT chk_order_status CHECK (status IN ('created', 'processing', 'shipped', 'delivered', 'cancelled')),
    CONSTRAINT fk_order_user FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE orders IS 'Оформленные заказы покупателей';
COMMENT ON COLUMN orders.id IS 'Суррогатный первичный ключ заказа';
COMMENT ON COLUMN orders.user_id IS 'Ссылка на покупателя, сделавшего заказ';
COMMENT ON COLUMN orders.status IS 'Статус заказа: created, processing, shipped, delivered, cancelled';
COMMENT ON COLUMN orders.total_amount IS 'Итоговая стоимость заказа в рублях';
COMMENT ON COLUMN orders.created_at IS 'Дата и время оформления заказа';


-- ====================================================================
-- 9. Таблица: order_items (Позиции заказа)
-- Связь: Ассоциативная таблица связи многие-ко-многим (orders <-> products)
-- ====================================================================
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,

    PRIMARY KEY (order_id, product_id),
    CONSTRAINT quantity_order_positive CHECK (quantity > 0),
    CONSTRAINT price_order_positive CHECK (unit_price > 0),
    CONSTRAINT fk_order_item_order FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_order_item_product FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE order_items IS 'Позиции товаров внутри оформленного заказа (связь M:N orders-products)';
COMMENT ON COLUMN order_items.order_id IS 'Ссылка на заказ (часть составного PK)';
COMMENT ON COLUMN order_items.product_id IS 'Ссылка на товар (часть составного PK)';
COMMENT ON COLUMN order_items.quantity IS 'Количество единиц товара в заказе';
COMMENT ON COLUMN order_items.unit_price IS 'Цена товара на момент оформления заказа (исторический слепок)';


-- ====================================================================
-- 10. Таблица: payments (Платежи по заказам)
-- Связь: 1:1 к orders
-- ====================================================================
CREATE TABLE payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    payment_status VARCHAR(30) DEFAULT 'waiting',
    paid_at TIMESTAMP,

    CONSTRAINT uq_payment_order UNIQUE (order_id),
    CONSTRAINT payment_positive CHECK (amount >= 0),
    CONSTRAINT chk_payment_status CHECK (payment_status IN ('waiting', 'completed', 'failed', 'refunded')),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE payments IS 'Финансовые транзакции оплаты заказов';
COMMENT ON COLUMN payments.id IS 'Суррогатный первичный ключ платежа';
COMMENT ON COLUMN payments.order_id IS 'Ссылка на оплачиваемый заказ';
COMMENT ON COLUMN payments.amount IS 'Сумма платежа в рублях';
COMMENT ON COLUMN payments.payment_status IS 'Статус транзакции: waiting, completed, failed, refunded';
COMMENT ON COLUMN payments.paid_at IS 'Метка времени фактического подтверждения оплаты';


-- ====================================================================
-- 11. Таблица: reviews (Отзывы и оценки покупателей)
-- Связи: 1:N от users (автор) и 1:N от products (товар)
-- ====================================================================
CREATE TABLE reviews (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT rating_check CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_review_user FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_review_product FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE reviews IS 'Отзывы и оценки товаров от покупателей площадки';
COMMENT ON COLUMN reviews.id IS 'Суррогатный первичный ключ отзыва';
COMMENT ON COLUMN reviews.user_id IS 'Ссылка на пользователя, оставившего отзыв';
COMMENT ON COLUMN reviews.product_id IS 'Ссылка на оцениваемый товар';
COMMENT ON COLUMN reviews.rating IS 'Оценка товара по пятибалльной шкале (от 1 до 5)';
COMMENT ON COLUMN reviews.comment IS 'Текстовый комментарий покупателя к товару';
COMMENT ON COLUMN reviews.created_at IS 'Дата и время публикации отзыва';


-- ====================================================================
-- 12. Таблица: addresses (Адреса доставки пользователей)
-- Связь: 1:N от users (у одного пользователя может быть несколько адресов)
-- ====================================================================
CREATE TABLE addresses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    city VARCHAR(100) NOT NULL,
    street VARCHAR(150) NOT NULL,
    house VARCHAR(20) NOT NULL,
    apartment VARCHAR(20),

    CONSTRAINT fk_address_user FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE addresses IS 'Адреса доставки, сохраненные пользователями';
COMMENT ON COLUMN addresses.id IS 'Суррогатный первичный ключ адреса';
COMMENT ON COLUMN addresses.user_id IS 'Ссылка на пользователя-владельца адреса';
COMMENT ON COLUMN addresses.city IS 'Город / населенный пункт';
COMMENT ON COLUMN addresses.street IS 'Улица / проспект / переулок';
COMMENT ON COLUMN addresses.house IS 'Номер дома / корпуса / строения';
COMMENT ON COLUMN addresses.apartment IS 'Номер квартиры / офиса';


-- ====================================================================
-- 13. Таблица: deliveries (Доставки заказов)
-- Связи: 1:1 к orders и 1:N от addresses
-- ====================================================================
CREATE TABLE deliveries (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    address_id BIGINT NOT NULL,
    delivery_status VARCHAR(30) DEFAULT 'created',
    delivery_date TIMESTAMP,

    CONSTRAINT uq_delivery_order UNIQUE (order_id),
    CONSTRAINT chk_delivery_status CHECK (delivery_status IN ('created', 'in_transit', 'delivered', 'cancelled')),
    CONSTRAINT fk_delivery_order FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_delivery_address FOREIGN KEY (address_id)
        REFERENCES addresses(id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

COMMENT ON TABLE deliveries IS 'Сведения о доставке заказов курьерской службой';
COMMENT ON COLUMN deliveries.id IS 'Суррогатный первичный ключ доставки';
COMMENT ON COLUMN deliveries.order_id IS 'Ссылка на доставляемый заказ (связь 1:1)';
COMMENT ON COLUMN deliveries.address_id IS 'Ссылка на целевой адрес доставки';
COMMENT ON COLUMN deliveries.delivery_status IS 'Статус доставки: created, in_transit, delivered, cancelled';
COMMENT ON COLUMN deliveries.delivery_date IS 'Фактическая или запланированная дата вручения заказа';


-- ====================================================================
-- Проверка успешного создания всех 13 таблиц схемы
-- ====================================================================
SELECT 
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns WHERE columns.table_name = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
ORDER BY table_name ASC;
