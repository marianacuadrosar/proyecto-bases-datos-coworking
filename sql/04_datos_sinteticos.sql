-- ============================================================
-- DATOS SINTÉTICOS PARA PRUEBAS DE RENDIMIENTO
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: 01_ddl.sql, 02_datos_prueba.sql,
-- 02_verificacion_datos.sql, 03_consultas.sql, 04_datos_sinteticos.sql,
-- 05_indices.sql y 06_consultas_analisis.sql.
--
-- Agrega 5.000 reservas sintéticas, cada una con su fila en
-- reserva_espacio, y una cuota pagada por cada reserva FINALIZADA.
-- En total son unas 14.400 filas nuevas. Con 200 reservas los
-- índices casi no se notan; con 5.200 el plan de ejecución cambia
-- de forma visible.
--
-- Las filas representan el histórico 2023-2024 de la red, migrado
-- desde el sistema anterior. Por eso:
--   - todas son anteriores a 2025 y no se cruzan con las reservas
--     de 02_datos_prueba.sql, que empiezan en enero de 2025;
--   - solo están FINALIZADAS (7 de cada 8) o CANCELADAS (1 de cada 8);
--   - solo las hacen los 35 clientes registrados hasta noviembre de
--     2022, repartidas por igual entre ellos;
--   - sus id son mayores que los de 02_datos_prueba.sql, aunque sus
--     fechas son anteriores.
--
-- Cumplen las mismas reglas que los datos de prueba:
--   - un espacio nunca tiene dos reservas el mismo día;
--   - la hora de inicio y fin cae dentro del horario de la sede;
--   - las cabinas, que no tienen tarifa por día, solo van por hora;
--   - tarifa_aplicada sale de la tabla tarifa;
--   - la cuota suma exactamente el valor de la reserva.
--
-- El script se puede correr varias veces: al empezar borra las
-- reservas anteriores a 2025 (solo existen si ya se había corrido)
-- y las vuelve a crear. Las cuotas y filas de reserva_espacio se
-- borran en cascada.
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;

SET @n_filas = 5000;         -- reservas que quedan al final
SET @n_candidatas = 5200;    -- se generan de más por si falta alguna tarifa
SET @desde   = '2023-01-02';
SET @dias    = 720;          -- días disponibles: hasta mediados de diciembre de 2024

SET SESSION cte_max_recursion_depth = 10000;


-- ------------------------------------------------------------
-- 0. Borrar una carga sintética anterior
-- ------------------------------------------------------------
DELETE FROM reserva
WHERE reserva_id IN (
    SELECT reserva_id FROM (
        SELECT DISTINCT re.reserva_id
        FROM reserva_espacio re
        WHERE re.inicio < '2025-01-01'
    ) AS previas
);


-- ------------------------------------------------------------
-- 1. Tablas auxiliares
-- ------------------------------------------------------------
DROP TABLE IF EXISTS sint_numeros;
DROP TABLE IF EXISTS sint_espacios;
DROP TABLE IF EXISTS sint_clientes;
DROP TABLE IF EXISTS sint_candidatas;
DROP TABLE IF EXISTS sint_reservas;

-- 0, 1, 2, ..., 4999
CREATE TABLE sint_numeros (i INT PRIMARY KEY);

INSERT INTO sint_numeros (i)
WITH RECURSIVE n AS (
    SELECT 0 AS i
    UNION ALL
    SELECT i + 1 FROM n WHERE i < @n_candidatas - 1
)
SELECT i FROM n;

-- Espacios numerados desde 0, con el horario de su sede
CREATE TABLE sint_espacios AS
SELECT
    ROW_NUMBER() OVER (ORDER BY e.espacio_id) - 1 AS rn,
    e.espacio_id,
    e.sede_id,
    e.tipo_id,
    s.hora_apertura,
    s.hora_cierre
FROM espacio e
JOIN sede s ON s.sede_id = e.sede_id;

ALTER TABLE sint_espacios ADD PRIMARY KEY (rn);

-- Clientes que ya existían en 2023
CREATE TABLE sint_clientes AS
SELECT
    ROW_NUMBER() OVER (ORDER BY cliente_id) - 1 AS rn,
    cliente_id
FROM cliente
WHERE fecha_registro <= '2022-11-30';

ALTER TABLE sint_clientes ADD PRIMARY KEY (rn);

SET @n_esp  = (SELECT COUNT(*) FROM sint_espacios);
SET @n_cli  = (SELECT COUNT(*) FROM sint_clientes);
SET @base   = (SELECT COALESCE(MAX(reserva_id), 0) FROM reserva);

-- Cada espacio recibe unas 17 reservas, separadas por @salto días.
-- Para un mismo espacio, la reserva k cae en el día k * @salto + r,
-- donde r es fijo para ese espacio. Así nunca coinciden dos el mismo día.
SET @salto  = FLOOR(@dias / CEIL(@n_candidatas / @n_esp));


-- ------------------------------------------------------------
-- 2. Cálculo de cada reserva sintética
-- ------------------------------------------------------------
-- Se generan 5.200 candidatas; el JOIN con TARIFA descarta las que no
-- tienen precio (por ejemplo, si 03_consultas.sql ya borró una tarifa).
CREATE TABLE sint_candidatas AS
SELECT
    x.*,
    t.valor AS tarifa_aplicada,
    ROUND(t.valor * CASE WHEN x.modalidad_id = 1
                         THEN TIMESTAMPDIFF(MINUTE, x.inicio, x.fin) / 60
                         ELSE 1 END, 2) AS valor_reserva
FROM (
    SELECT
        d.*,
        CASE WHEN d.modalidad_id = 2
             THEN TIMESTAMP(d.dia, d.hora_apertura)
             ELSE TIMESTAMP(d.dia, d.hora_apertura) + INTERVAL ((d.i DIV 7) % 6) HOUR
        END AS inicio,
        CASE WHEN d.modalidad_id = 2
             THEN TIMESTAMP(d.dia, d.hora_cierre)
             ELSE TIMESTAMP(d.dia, d.hora_apertura) + INTERVAL ((d.i DIV 7) % 6 + 1 + d.i % 4) HOUR
        END AS fin,
        d.dia - INTERVAL (d.i % 15) DAY AS fecha_creacion,
        CASE WHEN d.i % 8 = 0 THEN 'CANCELADA' ELSE 'FINALIZADA' END AS estado
    FROM (
        SELECT
            b.*,
            -- los domingos pasan al lunes
            b.dia0 + INTERVAL (DAYOFWEEK(b.dia0) = 1) DAY AS dia
        FROM (
            SELECT
                n.i,
                e.espacio_id,
                e.sede_id,
                e.tipo_id,
                e.hora_apertura,
                e.hora_cierre,
                c.cliente_id,
                -- una de cada tres por día, si el tipo tiene tarifa por día
                CASE WHEN n.i % 3 = 0
                      AND EXISTS (SELECT 1 FROM tarifa t2
                                  WHERE t2.sede_id = e.sede_id
                                    AND t2.tipo_id = e.tipo_id
                                    AND t2.modalidad_id = 2)
                     THEN 2 ELSE 1 END AS modalidad_id,
                DATE(@desde) + INTERVAL (FLOOR(n.i / @n_esp) * @salto + e.rn % @salto) DAY AS dia0
            FROM sint_numeros n
            JOIN sint_espacios e ON e.rn = n.i % @n_esp
            JOIN sint_clientes c ON c.rn = n.i % @n_cli
        ) AS b
    ) AS d
) AS x
JOIN tarifa t
  ON t.sede_id = x.sede_id
 AND t.tipo_id = x.tipo_id
 AND t.modalidad_id = x.modalidad_id;

-- Se queda con las primeras 5.000 y les asigna id en orden cronológico
CREATE TABLE sint_reservas AS
SELECT
    @base + ROW_NUMBER() OVER (ORDER BY c.inicio, c.espacio_id) AS reserva_id,
    c.*
FROM (
    SELECT ca.*, ROW_NUMBER() OVER (ORDER BY ca.i) AS orden
    FROM sint_candidatas ca
) AS c
WHERE c.orden <= @n_filas;


-- ------------------------------------------------------------
-- 3. Carga en las tablas reales
-- ------------------------------------------------------------
START TRANSACTION;

INSERT INTO reserva (reserva_id, fecha_creacion, estado, cliente_id, modalidad_id)
SELECT reserva_id, fecha_creacion, estado, cliente_id, modalidad_id
FROM sint_reservas
ORDER BY reserva_id;

INSERT INTO reserva_espacio (reserva_id, espacio_id, inicio, fin, tarifa_aplicada)
SELECT reserva_id, espacio_id, inicio, fin, tarifa_aplicada
FROM sint_reservas;

-- Una cuota pagada por cada reserva finalizada; las canceladas no tienen cuotas
INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
SELECT
    reserva_id,
    1,
    valor_reserva,
    GREATEST(fecha_creacion, dia - INTERVAL (i % 3) DAY),
    ELT(1 + i % 5, 'Tarjeta de crédito', 'Transferencia', 'PSE', 'Tarjeta débito', 'Nequi')
FROM sint_reservas
WHERE estado = 'FINALIZADA';

COMMIT;


-- ------------------------------------------------------------
-- 4. Limpieza y estadísticas
-- ------------------------------------------------------------
DROP TABLE sint_numeros;
DROP TABLE sint_espacios;
DROP TABLE sint_clientes;
DROP TABLE sint_candidatas;
DROP TABLE sint_reservas;

-- Actualiza las estadísticas que usa el optimizador en EXPLAIN
ANALYZE TABLE reserva, reserva_espacio, cuota;

SELECT 'reserva' AS tabla, COUNT(*) AS filas FROM reserva
UNION ALL SELECT 'reserva_espacio', COUNT(*) FROM reserva_espacio
UNION ALL SELECT 'cuota', COUNT(*) FROM cuota;
