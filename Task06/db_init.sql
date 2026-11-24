-- Лабораторная работа 6. База данных СТО.
-- Выполнять в новой базе. Время смен и записей — местное, YYYY-MM-DD HH:MM.
-- Цена хранится в копейках, чтобы расчёты не зависели от округления REAL.
PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

CREATE TABLE mechanics (
    id INTEGER PRIMARY KEY,
    last_name TEXT NOT NULL CHECK (trim(last_name) <> ''),
    first_name TEXT NOT NULL CHECK (trim(first_name) <> ''),
    patronymic TEXT CHECK (patronymic IS NULL OR trim(patronymic) <> ''),
    hired_on TEXT NOT NULL DEFAULT (date('now', 'localtime'))
        CHECK (date(hired_on, '+0 days') IS hired_on),
    -- Последний рабочий день. NULL означает, что мастер работает.
    dismissed_on TEXT CHECK (dismissed_on IS NULL OR (
        date(dismissed_on, '+0 days') IS dismissed_on AND dismissed_on >= hired_on
    )),
    commission_percent INTEGER NOT NULL CHECK (
        typeof(commission_percent) = 'integer' AND commission_percent BETWEEN 0 AND 100
    )
);

CREATE TABLE customers (
    id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL CHECK (trim(full_name) <> ''),
    phone TEXT NOT NULL CHECK (trim(phone) <> '')
);

CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE CHECK (trim(name) <> ''),
    duration_minutes INTEGER NOT NULL CHECK (
        typeof(duration_minutes) = 'integer' AND duration_minutes > 0
    ),
    price_kopecks INTEGER NOT NULL CHECK (typeof(price_kopecks) = 'integer' AND price_kopecks >= 0)
);

CREATE TABLE mechanic_services (
    mechanic_id INTEGER NOT NULL REFERENCES mechanics(id) ON DELETE RESTRICT,
    service_id INTEGER NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
    PRIMARY KEY (mechanic_id, service_id)
);

CREATE TABLE mechanic_shifts (
    id INTEGER PRIMARY KEY,
    mechanic_id INTEGER NOT NULL REFERENCES mechanics(id) ON DELETE RESTRICT,
    starts_at TEXT NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', starts_at, '+0 seconds') IS starts_at),
    ends_at TEXT NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', ends_at, '+0 seconds') IS ends_at),
    CHECK (starts_at < ends_at),
    UNIQUE (mechanic_id, starts_at)
);

CREATE TABLE appointments (
    id INTEGER PRIMARY KEY,
    shift_id INTEGER NOT NULL REFERENCES mechanic_shifts(id) ON DELETE RESTRICT,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    starts_at TEXT NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', starts_at, '+0 seconds') IS starts_at),
    ends_at TEXT NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', ends_at, '+0 seconds') IS ends_at),
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled')),
    CHECK (starts_at < ends_at)
);

CREATE TABLE appointment_services (
    appointment_id INTEGER NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    service_id INTEGER NOT NULL REFERENCES services(id) ON DELETE RESTRICT,
    -- Длительность на момент записи может отличаться от текущей в справочнике.
    duration_minutes INTEGER NOT NULL CHECK (
        typeof(duration_minutes) = 'integer' AND duration_minutes > 0
    ),
    PRIMARY KEY (appointment_id, service_id)
);

CREATE TABLE completed_jobs (
    id INTEGER PRIMARY KEY,
    mechanic_id INTEGER NOT NULL,
    service_id INTEGER NOT NULL,
    -- NULL для выполненной работы без предварительной записи.
    appointment_id INTEGER,
    completed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M', 'now', 'localtime'))
        CHECK (strftime('%Y-%m-%d %H:%M', completed_at, '+0 seconds') IS completed_at),
    -- Фактическая цена и процент на момент выполнения сохраняются для отчётов.
    price_kopecks INTEGER NOT NULL CHECK (typeof(price_kopecks) = 'integer' AND price_kopecks >= 0),
    commission_percent INTEGER NOT NULL CHECK (
        typeof(commission_percent) = 'integer' AND commission_percent BETWEEN 0 AND 100
    ),
    FOREIGN KEY (mechanic_id, service_id)
        REFERENCES mechanic_services(mechanic_id, service_id) ON DELETE RESTRICT,
    FOREIGN KEY (appointment_id, service_id)
        REFERENCES appointment_services(appointment_id, service_id) ON DELETE RESTRICT,
    UNIQUE (appointment_id, service_id)
);

CREATE INDEX idx_mechanics_name ON mechanics(last_name, first_name, id);
CREATE INDEX idx_mechanic_services_service ON mechanic_services(service_id, mechanic_id);
CREATE INDEX idx_appointments_shift_time ON appointments(shift_id, starts_at, ends_at);
CREATE INDEX idx_appointments_customer ON appointments(customer_id);
CREATE INDEX idx_appointment_services_service ON appointment_services(service_id);
CREATE INDEX idx_completed_jobs_mechanic_time ON completed_jobs(mechanic_id, completed_at);
CREATE INDEX idx_completed_jobs_time ON completed_jobs(completed_at);

-- Запись занимает полуоткрытый интервал [начало, конец).
-- Две записи могут стыковаться по времени, а отменённые записи слот освобождают.
CREATE VIEW invalid_appointments AS
SELECT a.id AS appointment_id
FROM appointments AS a
JOIN mechanic_shifts AS sh ON sh.id = a.shift_id
JOIN mechanics AS m ON m.id = sh.mechanic_id
WHERE (
    a.status <> 'cancelled'
    AND (
        a.starts_at < sh.starts_at OR a.ends_at > sh.ends_at
        OR date(a.starts_at) < m.hired_on
        OR (m.dismissed_on IS NOT NULL AND a.ends_at > (date(m.dismissed_on, '+1 day') || ' 00:00'))
        OR EXISTS (
            SELECT 1
            FROM appointments AS other
            JOIN mechanic_shifts AS other_shift ON other_shift.id = other.shift_id
            WHERE other_shift.mechanic_id = sh.mechanic_id
              AND other.id <> a.id AND other.status <> 'cancelled'
              AND other.starts_at < a.ends_at AND a.starts_at < other.ends_at
        )
    )
) OR EXISTS (
    SELECT 1
    FROM appointment_services AS line
    WHERE line.appointment_id = a.id AND NOT EXISTS (
        SELECT 1 FROM mechanic_services AS skill
        WHERE skill.mechanic_id = sh.mechanic_id AND skill.service_id = line.service_id
    )
) OR (
    SELECT COALESCE(SUM(line.duration_minutes), 0) * 60
    FROM appointment_services AS line
    WHERE line.appointment_id = a.id
) > CAST(strftime('%s', a.ends_at) AS INTEGER) - CAST(strftime('%s', a.starts_at) AS INTEGER)
OR EXISTS (
    SELECT 1 FROM completed_jobs AS job
    WHERE job.appointment_id = a.id
      AND (a.status = 'cancelled' OR job.mechanic_id <> sh.mechanic_id)
);

CREATE TRIGGER check_new_appointment
AFTER INSERT ON appointments
WHEN EXISTS (SELECT 1 FROM invalid_appointments WHERE appointment_id = NEW.id)
BEGIN
    SELECT RAISE(ABORT, 'Appointment is outside the shift or the mechanic is unavailable');
END;

CREATE TRIGGER check_updated_appointment
AFTER UPDATE OF shift_id, starts_at, ends_at, status ON appointments
WHEN EXISTS (SELECT 1 FROM invalid_appointments WHERE appointment_id = NEW.id)
BEGIN
    SELECT RAISE(ABORT, 'Appointment change conflicts with the schedule, services or completed work');
END;

-- Запись и её услуги добавляются в одной транзакции приложения.
CREATE TRIGGER check_new_appointment_service
AFTER INSERT ON appointment_services
WHEN EXISTS (SELECT 1 FROM invalid_appointments WHERE appointment_id = NEW.appointment_id)
BEGIN
    SELECT RAISE(ABORT, 'The service is unavailable for this mechanic or does not fit the slot');
END;

CREATE TRIGGER check_updated_appointment_service
AFTER UPDATE ON appointment_services
WHEN EXISTS (SELECT 1 FROM invalid_appointments WHERE appointment_id = NEW.appointment_id)
BEGIN
    SELECT RAISE(ABORT, 'The service is unavailable for this mechanic or does not fit the slot');
END;

CREATE TRIGGER protect_booked_shift
BEFORE UPDATE OF mechanic_id, starts_at, ends_at ON mechanic_shifts
WHEN EXISTS (
    SELECT 1 FROM appointments AS a
    WHERE a.shift_id = OLD.id
      AND (NEW.mechanic_id <> OLD.mechanic_id OR (
          a.status <> 'cancelled' AND (a.starts_at < NEW.starts_at OR a.ends_at > NEW.ends_at)
      ))
)
BEGIN
    SELECT RAISE(ABORT, 'Shift change conflicts with an existing appointment');
END;

-- Состав услуг мастера хранится вместе с историей. Связь, которая уже
-- используется в записи, нельзя удалить или переназначить другой паре.
CREATE TRIGGER protect_booked_qualification_delete
AFTER DELETE ON mechanic_services
WHEN EXISTS (
    SELECT 1
    FROM appointment_services AS line
    JOIN appointments AS a ON a.id = line.appointment_id
    JOIN mechanic_shifts AS sh ON sh.id = a.shift_id
    WHERE sh.mechanic_id = OLD.mechanic_id AND line.service_id = OLD.service_id
)
BEGIN
    SELECT RAISE(ABORT, 'A service used in an appointment cannot be removed from the mechanic');
END;

CREATE TRIGGER protect_booked_qualification_update
AFTER UPDATE OF mechanic_id, service_id ON mechanic_services
WHEN (NEW.mechanic_id <> OLD.mechanic_id OR NEW.service_id <> OLD.service_id)
AND EXISTS (
    SELECT 1
    FROM appointment_services AS line
    JOIN appointments AS a ON a.id = line.appointment_id
    JOIN mechanic_shifts AS sh ON sh.id = a.shift_id
    WHERE sh.mechanic_id = OLD.mechanic_id AND line.service_id = OLD.service_id
)
BEGIN
    SELECT RAISE(ABORT, 'A service used in an appointment cannot be reassigned');
END;

CREATE VIEW invalid_completed_jobs AS
SELECT j.id AS job_id
FROM completed_jobs AS j
JOIN mechanics AS m ON m.id = j.mechanic_id
WHERE date(j.completed_at) < m.hired_on
   OR date(j.completed_at) > m.dismissed_on
   OR EXISTS (SELECT 1 FROM invalid_appointments WHERE appointment_id = j.appointment_id);

CREATE TRIGGER check_new_job_appointment
AFTER INSERT ON completed_jobs
WHEN EXISTS (SELECT 1 FROM invalid_completed_jobs WHERE job_id = NEW.id)
BEGIN
    SELECT RAISE(ABORT, 'Completed work conflicts with the appointment or employment dates');
END;

CREATE TRIGGER check_updated_job_appointment
AFTER UPDATE OF mechanic_id, service_id, appointment_id, completed_at ON completed_jobs
WHEN EXISTS (SELECT 1 FROM invalid_completed_jobs WHERE job_id = NEW.id)
BEGIN
    SELECT RAISE(ABORT, 'Completed work conflicts with the appointment or employment dates');
END;

CREATE TRIGGER protect_employment_history
AFTER UPDATE OF hired_on, dismissed_on ON mechanics
WHEN EXISTS (
    SELECT 1 FROM invalid_completed_jobs AS invalid
    JOIN completed_jobs AS job ON job.id = invalid.job_id
    WHERE job.mechanic_id = NEW.id
) OR EXISTS (
    SELECT 1 FROM invalid_appointments AS invalid
    JOIN appointments AS a ON a.id = invalid.appointment_id
    JOIN mechanic_shifts AS sh ON sh.id = a.shift_id
    WHERE sh.mechanic_id = NEW.id
)
BEGIN
    SELECT RAISE(ABORT, 'Employment date change conflicts with existing appointments or completed work');
END;

-- Изменения справочника не изменяют сумму уже выполненной работы.
-- В представление входят работы всех мастеров, в том числе уволенных.
CREATE VIEW completed_work_details AS
SELECT j.id AS job_id, m.id AS mechanic_id,
       m.last_name, m.first_name, m.patronymic,
       s.id AS service_id, s.name AS service_name,
       j.completed_at, j.price_kopecks, j.commission_percent
FROM completed_jobs AS j
JOIN mechanics AS m ON m.id = j.mechanic_id
JOIN services AS s ON s.id = j.service_id;

-- Тестовые данные.
INSERT INTO mechanics (id, last_name, first_name, patronymic, hired_on, dismissed_on, commission_percent)
VALUES
    (1, 'Иванов', 'Илья', 'Андреевич', '2023-04-03', NULL, 35),
    (2, 'Соколова', 'Мария', 'Олеговна', '2023-08-14', NULL, 40),
    (3, 'Ким', 'Артём', 'Сергеевич', '2024-01-11', NULL, 30),
    (4, 'Орлов', 'Павел', 'Викторович', '2022-11-08', '2025-03-31', 25);

INSERT INTO customers (id, full_name, phone)
VALUES
    (1, 'Анна Лебедева', '+7 000 000-00-01'),
    (2, 'Константин Миронов', '+7 000 000-00-02'),
    (3, 'Елена Романова', '+7 000 000-00-03'),
    (4, 'Алексей Беляев', '+7 000 000-00-04');

INSERT INTO services (id, name, duration_minutes, price_kopecks)
VALUES
    (1, 'Диагностика', 45, 180000),
    (2, 'Замена масла', 30, 120000),
    (3, 'Шиномонтаж', 60, 280000),
    (4, 'Замена тормозных колодок', 90, 420000),
    (5, 'Регулировка сход-развала', 45, 260000);

INSERT INTO mechanic_services (mechanic_id, service_id)
VALUES (1, 1), (1, 2), (1, 4), (2, 1), (2, 3), (2, 5), (3, 2), (3, 4), (4, 5);

INSERT INTO mechanic_shifts (id, mechanic_id, starts_at, ends_at)
VALUES
    (1, 1, '2025-03-20 09:00', '2025-03-20 18:00'),
    (2, 2, '2025-03-21 10:00', '2025-03-21 19:00'),
    (3, 4, '2025-03-25 09:00', '2025-03-25 17:00'),
    (4, 3, '2025-03-24 08:00', '2025-03-24 16:00'),
    (5, 1, date('now', 'localtime', '+1 day') || ' 09:00', date('now', 'localtime', '+1 day') || ' 18:00'),
    (6, 2, date('now', 'localtime', '+1 day') || ' 10:00', date('now', 'localtime', '+1 day') || ' 19:00'),
    (7, 3, date('now', 'localtime', '+1 day') || ' 08:00', date('now', 'localtime', '+1 day') || ' 16:00'),
    (8, 1, date('now', 'localtime', '+2 days') || ' 09:00', date('now', 'localtime', '+2 days') || ' 18:00');

INSERT INTO appointments (id, shift_id, customer_id, starts_at, ends_at, status)
VALUES
    (1, 1, 1, '2025-03-20 10:00', '2025-03-20 11:15', 'completed'),
    (2, 2, 2, '2025-03-21 11:00', '2025-03-21 12:00', 'completed'),
    (3, 3, 3, '2025-03-25 10:00', '2025-03-25 10:45', 'completed');

WITH demo_appointments(id, shift_id, customer_id, start_time, end_time, status) AS (
    VALUES (4, 5, 2, '10:00', '10:45', 'scheduled'),
           (5, 6, 4, '11:00', '12:00', 'scheduled'),
           (6, 5, 3, '10:15', '10:45', 'cancelled'),
           (7, 8, 1, '09:00', '10:15', 'scheduled')
)
INSERT INTO appointments (id, shift_id, customer_id, starts_at, ends_at, status)
SELECT a.id, a.shift_id, a.customer_id,
       date(sh.starts_at) || ' ' || a.start_time,
       date(sh.starts_at) || ' ' || a.end_time, a.status
FROM demo_appointments AS a
JOIN mechanic_shifts AS sh ON sh.id = a.shift_id;

INSERT INTO appointment_services (appointment_id, service_id, duration_minutes)
VALUES (1, 1, 45), (1, 2, 30), (2, 3, 60), (3, 5, 45),
       (4, 1, 45), (5, 3, 60), (6, 2, 30), (7, 1, 45), (7, 2, 30);

INSERT INTO completed_jobs (mechanic_id, service_id, appointment_id, completed_at, price_kopecks, commission_percent)
VALUES
    (1, 1, 1, '2025-03-20 10:45', 170000, 35),
    (1, 2, 1, '2025-03-20 11:15', 120000, 35),
    (2, 3, 2, '2025-03-21 12:00', 280000, 40),
    (3, 4, NULL, '2025-03-24 11:30', 400000, 30),
    (4, 5, 3, '2025-03-25 10:45', 240000, 25),
    (2, 1, NULL, '2025-03-21 15:15', 180000, 40);

COMMIT;

-- Пример расчёта зарплаты в копейках. Конец периода не включается.
-- SELECT mechanic_id, SUM(price_kopecks) AS revenue_kopecks,
--        (SUM(price_kopecks * commission_percent) + 50) / 100 AS pay_kopecks
-- FROM completed_work_details
-- WHERE completed_at >= '2025-03-01 00:00' AND completed_at < '2025-04-01 00:00'
-- GROUP BY mechanic_id;
-- Пример статистики по видам услуг.
-- SELECT service_id, service_name, COUNT(*) AS jobs, SUM(price_kopecks) AS revenue_kopecks
-- FROM completed_work_details
-- GROUP BY service_id, service_name;
