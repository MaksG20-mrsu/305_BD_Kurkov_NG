-- Task05: run once after db_init.sql. UTF-8.
-- All relationships use generated keys or lookup by unique values.
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

INSERT INTO occupations (name)
SELECT 'student'
WHERE NOT EXISTS (SELECT 1 FROM occupations WHERE name = 'student');

-- Registration dates use the users.register_date system-time default.
-- example.com addresses are fictional addresses for this assignment.
INSERT INTO users (first_name, last_name, email, gender, occupation_id)
VALUES
    ('Айрат', 'Кашаев', 'kashaev.airat.task05@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student')),
    ('Софья', 'Кудашкина', 'kudashkina.sofya.task05@example.com', 'female',
        (SELECT id FROM occupations WHERE name = 'student')),
    ('Никита', 'Курков', 'kurkov.nikita.task05@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student')),
    ('Виктория', 'Лаптева', 'lapteva.viktoriya.task05@example.com', 'female',
        (SELECT id FROM occupations WHERE name = 'student')),
    ('Александр', 'Лушаев', 'lushaev.aleksandr.task05@example.com', 'male',
        (SELECT id FROM occupations WHERE name = 'student'));

INSERT INTO genres (name)
SELECT 'Sci-Fi' WHERE NOT EXISTS (SELECT 1 FROM genres WHERE name = 'Sci-Fi');
INSERT INTO genres (name)
SELECT 'Animation' WHERE NOT EXISTS (SELECT 1 FROM genres WHERE name = 'Animation');
INSERT INTO genres (name)
SELECT 'Drama' WHERE NOT EXISTS (SELECT 1 FROM genres WHERE name = 'Drama');

-- Capture each generated movie ID immediately in this connection.
-- The temporary mapping is removed before COMMIT.
CREATE TEMP TABLE task05_new_movies (
    movie_id INTEGER PRIMARY KEY,
    genre_name TEXT NOT NULL,
    my_rating REAL NOT NULL CHECK (my_rating BETWEEN 0 AND 5)
);

INSERT INTO movies (title, year) VALUES ('Дюна: Часть вторая', 2024);
INSERT INTO task05_new_movies (movie_id, genre_name, my_rating)
VALUES (last_insert_rowid(), 'Sci-Fi', 5.0);

INSERT INTO movies (title, year) VALUES ('Головоломка 2', 2024);
INSERT INTO task05_new_movies (movie_id, genre_name, my_rating)
VALUES (last_insert_rowid(), 'Animation', 4.5);

INSERT INTO movies (title, year) VALUES ('Оставленные', 2023);
INSERT INTO task05_new_movies (movie_id, genre_name, my_rating)
VALUES (last_insert_rowid(), 'Drama', 4.0);

INSERT INTO movie_genres (movie_id, genre_id)
SELECT n.movie_id, g.id
FROM task05_new_movies AS n
JOIN genres AS g ON g.name = n.genre_name;

-- Timestamp uses the ratings.timestamp system-time default.
INSERT INTO ratings (user_id, movie_id, rating)
SELECT u.id, n.movie_id, n.my_rating
FROM users AS u
CROSS JOIN task05_new_movies AS n
WHERE u.email = 'kurkov.nikita.task05@example.com';

DROP TABLE task05_new_movies;
COMMIT;
