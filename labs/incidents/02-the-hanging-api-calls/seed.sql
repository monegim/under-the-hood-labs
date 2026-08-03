CREATE DATABASE IF NOT EXISTS appdb;
USE appdb;

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    item VARCHAR(200) NOT NULL
);

-- 20 ordinary small customers: 5 rows each. Their reports easily fit in
-- one or two small TCP segments - these never trigger the incident.
DELIMITER $$
CREATE PROCEDURE seed_small()
BEGIN
    DECLARE c INT DEFAULT 1;
    DECLARE i INT;
    WHILE c <= 20 DO
        SET i = 1;
        WHILE i <= 5 DO
            INSERT INTO orders (customer_id, item)
                VALUES (c, CONCAT('order-', c, '-', i, '-widget'));
            SET i = i + 1;
        END WHILE;
        SET c = c + 1;
    END WHILE;
END$$
DELIMITER ;
CALL seed_small();
DROP PROCEDURE seed_small;

-- customer 999 ("acme-corp") is a large enterprise account: 3000 rows of
-- ~200 bytes each, so its report is a few hundred KB - guaranteed to
-- span many TCP segments at the path's real MTU.
DELIMITER $$
CREATE PROCEDURE seed_big()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 3000 DO
        INSERT INTO orders (customer_id, item)
            VALUES (999, CONCAT('acme-order-', i, '-', REPEAT('x', 150)));
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL seed_big();
DROP PROCEDURE seed_big;
