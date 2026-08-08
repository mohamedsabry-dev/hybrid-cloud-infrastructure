CREATE DATABASE webstore;
\c webstore
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    price NUMERIC(10,2)
);
INSERT INTO products (name, price) VALUES
    ('Laptop', 999.99),
    ('Keyboard', 49.99),
    ('Monitor', 299.99);

CREATE USER webuser WITH PASSWORD 'web123';
GRANT CONNECT ON DATABASE webstore TO webuser;
\c webstore
GRANT SELECT ON products TO webuser;
