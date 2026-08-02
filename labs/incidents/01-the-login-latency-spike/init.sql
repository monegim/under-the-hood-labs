CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    password VARCHAR(64) NOT NULL
);

INSERT INTO users (username, password) VALUES ('demo', 'demopass')
    ON DUPLICATE KEY UPDATE username = username;
