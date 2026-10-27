#!/bin/bash
chcp 65001 2>/dev/null || true

sqlite3 -bail movies_rating.db < db_init.sql

echo "1. Пары разных пользователей, оценивших один фильм. Без дубликатов, первые 100 записей."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
SELECT DISTINCT
       u1.name AS user_1,
       u2.name AS user_2,
       m.title AS movie
FROM ratings AS r1
JOIN ratings AS r2
  ON r1.movie_id = r2.movie_id
 AND r1.user_id < r2.user_id
JOIN users AS u1 ON u1.id = r1.user_id
JOIN users AS u2 ON u2.id = r2.user_id
JOIN movies AS m ON m.id = r1.movie_id
ORDER BY m.id, u1.id, u2.id
LIMIT 100;
"
echo " "

echo "2. Десять самых свежих оценок от разных пользователей."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
WITH latest AS (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY user_id
               ORDER BY timestamp DESC, id DESC
           ) AS rn
    FROM ratings AS r
)
SELECT m.title AS movie,
       u.name AS user_name,
       r.rating,
       date(r.timestamp, 'unixepoch') AS rating_date
FROM latest AS r
JOIN movies AS m ON m.id = r.movie_id
JOIN users AS u ON u.id = r.user_id
WHERE r.rn = 1
ORDER BY r.timestamp DESC, r.id DESC
LIMIT 10;
"
echo " "

echo "3. Все фильмы с максимальным и минимальным средним рейтингом."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
WITH averages AS (
    SELECT m.id,
           m.title,
           m.year,
           AVG(r.rating) AS avg_rating
    FROM movies AS m
    JOIN ratings AS r ON r.movie_id = m.id
    GROUP BY m.id, m.title, m.year
),
bounds AS (
    SELECT MAX(avg_rating) AS max_rating,
           MIN(avg_rating) AS min_rating
    FROM averages
)
SELECT a.title,
       a.year,
       a.avg_rating,
       CASE
           WHEN a.avg_rating = b.max_rating THEN 'Да'
           ELSE 'Нет'
       END AS 'Рекомендуем'
FROM averages AS a
CROSS JOIN bounds AS b
WHERE a.avg_rating = b.max_rating
   OR a.avg_rating = b.min_rating
ORDER BY a.year, a.title, a.id;
"
echo " "

echo "4. Количество и среднее значение оценок женщин за 2010-2012 годы включительно."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
SELECT COUNT(*) AS rating_count,
       AVG(r.rating) AS avg_rating
FROM ratings AS r
JOIN users AS u ON u.id = r.user_id
WHERE u.gender = 'female'
  AND date(r.timestamp, 'unixepoch') >= '2010-01-01'
  AND date(r.timestamp, 'unixepoch') < '2013-01-01';
"
echo " "

echo "5. Средняя оценка и место фильма в рейтинге. Первые 20 по году и названию."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
WITH averages AS (
    SELECT m.id,
           m.title,
           m.year,
           AVG(r.rating) AS avg_rating
    FROM movies AS m
    JOIN ratings AS r ON r.movie_id = m.id
    GROUP BY m.id, m.title, m.year
),
ranked AS (
    SELECT *,
           RANK() OVER (
               ORDER BY avg_rating DESC
           ) AS rating_place
    FROM averages
)
SELECT title,
       year,
       avg_rating,
       rating_place
FROM ranked
ORDER BY year, title, id
LIMIT 20;
"
echo " "

echo "6. Десять последних зарегистрированных пользователей: Фамилия Имя|Дата регистрации."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -noheader -list -echo "
SELECT substr(name, instr(name, ' ') + 1)
       || ' ' ||
       substr(name, 1, instr(name, ' ') - 1)
       || '|' ||
       date(register_date)
FROM users
ORDER BY register_date DESC, id DESC
LIMIT 10;
"
echo " "

echo "7. Таблица умножения чисел от 1 до 10 с помощью рекурсивного CTE."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -noheader -list -echo "
WITH RECURSIVE numbers(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 10
)
SELECT a.n || 'x' || b.n || '=' || (a.n * b.n)
       AS multiplication
FROM numbers AS a
CROSS JOIN numbers AS b
ORDER BY a.n, b.n;
"
echo " "

echo "8. Все уникальные жанры фильмов, по одному в строке, с помощью рекурсивного CTE."
echo "--------------------------------------------------"
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE split(genre, rest) AS (
    SELECT '',
           genres || '|'
    FROM movies
    WHERE genres IS NOT NULL
      AND genres <> ''
      AND genres <> '(no genres listed)'

    UNION ALL

    SELECT substr(rest, 1, instr(rest, '|') - 1),
           substr(rest, instr(rest, '|') + 1)
    FROM split
    WHERE rest <> ''
)
SELECT DISTINCT genre
FROM split
WHERE genre <> ''
ORDER BY genre;
"
echo " "
