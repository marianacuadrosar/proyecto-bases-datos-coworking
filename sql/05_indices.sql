-- ============================================================
-- ÍNDICES Y RENDIMIENTO
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: 01_ddl.sql, 02_datos_prueba.sql,
-- 02_verificacion_datos.sql, 03_consultas.sql, 04_datos_sinteticos.sql,
-- 05_indices.sql y 06_consultas_analisis.sql.
--
-- Si antes se corrió 03_consultas.sql, algunos conteos cambian en una
-- o dos filas (por ejemplo, hay una reserva confirmada más).
--
-- Sin los datos sintéticos las tablas tienen 200 reservas y la
-- diferencia casi no se ve. Con ellos, reserva tiene 5.200 filas,
-- reserva_espacio unas 5.240 y cuota unas 4.580.
--
-- Cada índice sigue el mismo esquema:
--   consulta que lo necesita -> EXPLAIN antes -> CREATE INDEX ->
--   EXPLAIN después -> justificación.
--
-- EXPLAIN muestra el plan que elige MySQL. EXPLAIN ANALYZE además
-- ejecuta la consulta y mide el tiempo real (MySQL 8.0.18 o superior).
-- Los tiempos anotados en los comentarios son la mediana de cuatro
-- ejecuciones en MySQL 8.0.46. En otro equipo cambian, pero la
-- proporción entre antes y después se mantiene.
--
-- Cómo leer EXPLAIN:
--   type  ALL   = recorre la tabla completa
--   type  ref   = busca un valor exacto en el índice
--   type  range = recorre solo un rango del índice
--   rows        = filas que MySQL estima que tiene que leer
--   Using filesort       = tuvo que ordenar en memoria después de leer
--   Backward index scan  = leyó el índice al revés para el ORDER BY DESC
-- ============================================================

USE coworking_db;

ANALYZE TABLE reserva, reserva_espacio, cuota;


-- ------------------------------------------------------------
-- 0. Punto de partida
-- ------------------------------------------------------------
-- InnoDB ya crea un índice por cada llave primaria y por cada llave
-- foránea. Estos son los que existen antes de agregar los nuestros:
--   reserva:          PRIMARY (reserva_id), cliente_id, modalidad_id
--   reserva_espacio:  PRIMARY (reserva_id, espacio_id), espacio_id
--   cuota:            PRIMARY (reserva_id, num_cuota)
-- Ninguno sirve para filtrar por estado, por fecha de uso o por
-- fecha de pago.

-- Si el script ya se corrió, borra los índices para que el EXPLAIN
-- de "antes" vuelva a mostrar la tabla sin ellos.
-- (MySQL 8 no tiene DROP INDEX IF EXISTS.)
SET @sql = IF((SELECT COUNT(*) FROM information_schema.statistics
               WHERE table_schema = DATABASE() AND table_name = 'reserva'
                 AND index_name = 'idx_reserva_estado_fecha') > 0,
              'DROP INDEX idx_reserva_estado_fecha ON reserva', 'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql = IF((SELECT COUNT(*) FROM information_schema.statistics
               WHERE table_schema = DATABASE() AND table_name = 'reserva_espacio'
                 AND index_name = 'idx_reserva_espacio_inicio') > 0,
              'DROP INDEX idx_reserva_espacio_inicio ON reserva_espacio', 'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql = IF((SELECT COUNT(*) FROM information_schema.statistics
               WHERE table_schema = DATABASE() AND table_name = 'cuota'
                 AND index_name = 'idx_cuota_pago_monto') > 0,
              'DROP INDEX idx_cuota_pago_monto ON cuota', 'DO 0');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SHOW INDEX FROM reserva;
SHOW INDEX FROM reserva_espacio;
SHOW INDEX FROM cuota;


-- ============================================================
-- ÍNDICE 1: reserva (estado, fecha_creacion)
-- ============================================================
--
-- Consulta que lo usa: la consulta de estructura que lista las
-- reservas confirmadas de la más reciente a la más antigua. Es también la
-- lista que la aplicación mostrará en recepción todos los días,
-- con CONFIRMADA o con PENDIENTE.

-- ANTES
EXPLAIN
SELECT reserva_id, cliente_id, fecha_creacion, modalidad_id, estado
FROM reserva
WHERE estado = 'CONFIRMADA'
ORDER BY fecha_creacion DESC;

EXPLAIN ANALYZE
SELECT reserva_id, cliente_id, fecha_creacion, modalidad_id, estado
FROM reserva
WHERE estado = 'CONFIRMADA'
ORDER BY fecha_creacion DESC;

-- Resultado medido:
--   type ALL, rows 5200, Extra: Using where; Using filesort
--   costo estimado 524, tiempo real 1,6 ms
--   Lee las 5.200 reservas para devolver 24 y después las ordena.

CREATE INDEX idx_reserva_estado_fecha
    ON reserva (estado, fecha_creacion);

-- DESPUÉS
EXPLAIN
SELECT reserva_id, cliente_id, fecha_creacion, modalidad_id, estado
FROM reserva
WHERE estado = 'CONFIRMADA'
ORDER BY fecha_creacion DESC;

EXPLAIN ANALYZE
SELECT reserva_id, cliente_id, fecha_creacion, modalidad_id, estado
FROM reserva
WHERE estado = 'CONFIRMADA'
ORDER BY fecha_creacion DESC;

-- Resultado medido:
--   type ref, key idx_reserva_estado_fecha, rows 24,
--   Extra: Backward index scan (ya no hay filesort)
--   costo estimado 8,4, tiempo real 0,14 ms
--
-- Por qué estas columnas y en este orden:
--   - estado va primero porque la consulta lo compara por igualdad.
--     Solo tiene cuatro valores, así que un índice sobre estado solo
--     no ayudaría con FINALIZADA (87 % de las filas). Sí ayuda con
--     CONFIRMADA y PENDIENTE, que son menos del 1 % y son los estados
--     que se consultan a diario.
--   - fecha_creacion va segunda: dentro de cada estado, el índice ya
--     guarda las filas ordenadas por fecha, y MySQL las lee en ese
--     orden en vez de ordenarlas después.
--   - Al revés, (fecha_creacion, estado), MySQL no podría saltar
--     directo a las CONFIRMADAS y tendría que recorrer todo el índice.


-- ============================================================
-- ÍNDICE 2: reserva_espacio (inicio)
-- ============================================================
--
-- Consultas que lo usan: la agenda de una semana (abajo) y los
-- consultas de análisis por periodo (6, 7, 8, 9 y 11),
-- que filtran por rango de re.inicio.

-- ANTES: agenda de la semana del 16 al 22 de noviembre de 2026
EXPLAIN
SELECT reserva_id, espacio_id, inicio, fin
FROM reserva_espacio
WHERE inicio >= '2026-11-16'
  AND inicio <  '2026-11-23'
ORDER BY inicio;

EXPLAIN ANALYZE
SELECT reserva_id, espacio_id, inicio, fin
FROM reserva_espacio
WHERE inicio >= '2026-11-16'
  AND inicio <  '2026-11-23'
ORDER BY inicio;

-- ANTES: consulta de análisis 9 (reservas por mes en 2026)
EXPLAIN
SELECT DATE_FORMAT(re.inicio, '%Y-%m') AS mes,
       COUNT(DISTINCT r.reserva_id)    AS reservas,
       ROUND(SUM(re.tarifa_aplicada *
                 CASE WHEN m.nombre = 'Hora'
                      THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                      ELSE 1 END))     AS valor_reservado
FROM reserva_espacio re
INNER JOIN reserva r ON r.reserva_id = re.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE r.estado <> 'CANCELADA'
  AND re.inicio >= '2026-01-01'
  AND re.inicio <  '2027-01-01'
GROUP BY mes
ORDER BY mes;

-- Resultado medido:
--   Agenda:    type ALL, rows 5237, Using where; Using filesort
--              costo 528, tiempo real 1,3 ms
--   Consulta 9: la tabla re se lee completa (type ALL, rows 5237)

CREATE INDEX idx_reserva_espacio_inicio
    ON reserva_espacio (inicio);

-- DESPUÉS
EXPLAIN
SELECT reserva_id, espacio_id, inicio, fin
FROM reserva_espacio
WHERE inicio >= '2026-11-16'
  AND inicio <  '2026-11-23'
ORDER BY inicio;

EXPLAIN ANALYZE
SELECT reserva_id, espacio_id, inicio, fin
FROM reserva_espacio
WHERE inicio >= '2026-11-16'
  AND inicio <  '2026-11-23'
ORDER BY inicio;

EXPLAIN
SELECT DATE_FORMAT(re.inicio, '%Y-%m') AS mes,
       COUNT(DISTINCT r.reserva_id)    AS reservas,
       ROUND(SUM(re.tarifa_aplicada *
                 CASE WHEN m.nombre = 'Hora'
                      THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                      ELSE 1 END))     AS valor_reservado
FROM reserva_espacio re
INNER JOIN reserva r ON r.reserva_id = re.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE r.estado <> 'CANCELADA'
  AND re.inicio >= '2026-01-01'
  AND re.inicio <  '2027-01-01'
GROUP BY mes
ORDER BY mes;

-- Resultado medido:
--   Agenda:    type range, key idx_reserva_espacio_inicio, rows 7,
--              sin filesort; costo 3,4, tiempo real 0,06 ms
--   Consulta 9: re pasa a type range con rows 156
--
-- Por qué esta columna:
--   - Casi todos los reportes preguntan por un periodo: esta semana,
--     este mes, este año. Ese periodo está en inicio.
--   - Ningún índice existente empieza por inicio. La llave primaria
--     empieza por reserva_id y el índice de la llave foránea por
--     espacio_id; un índice solo sirve si la consulta usa su primera
--     columna.
--   - inicio casi no se repite (fecha y hora), así que un rango de una
--     semana descarta casi toda la tabla.
--
-- Por qué no (espacio_id, inicio):
--   Para saber si un espacio está libre se filtra por espacio_id, y
--   esa columna ya tiene el índice de la llave foránea. Cada espacio
--   tiene unas 18 reservas, así que esa búsqueda ya es rápida. Un
--   índice compuesto duplicaría casi lo mismo.


-- ============================================================
-- ÍNDICE 3: cuota (fecha_pago, monto)
-- ============================================================
--
-- Consultas que lo usan: la consulta de estructura que lista las
-- cuotas sin fecha de pago ordenadas por monto, las consultas de
-- análisis 5 y 12 (cartera por cobrar) y las 2 y 4 (pagos en un
-- rango de fechas).

-- ANTES
EXPLAIN
SELECT reserva_id, num_cuota, monto, fecha_pago, metodo_pago
FROM cuota
WHERE fecha_pago IS NULL
ORDER BY monto DESC;

EXPLAIN ANALYZE
SELECT reserva_id, num_cuota, monto, fecha_pago, metodo_pago
FROM cuota
WHERE fecha_pago IS NULL
ORDER BY monto DESC;

-- Resultado medido:
--   type ALL, rows 4581, Using where; Using filesort
--   costo 462, tiempo real 1,7 ms

CREATE INDEX idx_cuota_pago_monto
    ON cuota (fecha_pago, monto);

-- DESPUÉS
EXPLAIN
SELECT reserva_id, num_cuota, monto, fecha_pago, metodo_pago
FROM cuota
WHERE fecha_pago IS NULL
ORDER BY monto DESC;

EXPLAIN ANALYZE
SELECT reserva_id, num_cuota, monto, fecha_pago, metodo_pago
FROM cuota
WHERE fecha_pago IS NULL
ORDER BY monto DESC;

-- Resultado medido:
--   type ref, key idx_cuota_pago_monto, rows 34,
--   Extra: Using where; Backward index scan (sin filesort)
--   costo 11,9, tiempo real 0,10 ms
--
-- Por qué estas columnas:
--   - Las cuotas sin pagar son menos del 1 % (34 de 4.581). Buscarlas
--     recorriendo toda la tabla es el peor caso posible.
--   - En MySQL, un índice B-tree también guarda los NULL, y IS NULL
--     se resuelve como búsqueda exacta (type ref).
--   - monto va segundo para que, dentro de las cuotas sin pagar, las
--     filas ya estén ordenadas por valor.
--   - Las consultas de pagos entre dos fechas usan la misma primera
--     columna con un rango.


-- ============================================================
-- COLUMNAS QUE NO SE INDEXARON
-- ============================================================
--   - Llaves foráneas (cliente_id, espacio_id, modalidad_id, sede_id,
--     tipo_id): InnoDB ya les creó índice.
--   - cliente.email: si se agrega UNIQUE (email), como se recomendó
--     para el DDL, MySQL crea el índice solo. Otro sería duplicado.
--   - reserva.modalidad_id y cliente.tipo_cliente: dos valores cada
--     una; el índice no descarta casi nada.
--   - sede.ciudad: sede tiene 50 filas. Leerla completa cuesta menos
--     que usar un índice.
--
-- COSTO DE LOS ÍNDICES
--   Cada índice ocupa espacio y hace un poco más lento cada INSERT y
--   UPDATE, porque MySQL tiene que actualizarlo. Una reserva se crea
--   una vez y se consulta muchas veces (agenda, cobranza, reportes),
--   así que el costo compensa. Espacio ocupado por cada índice:

SELECT
    table_name,
    index_name,
    ROUND(stat_value * @@innodb_page_size / 1024) AS tamano_kb
FROM mysql.innodb_index_stats
WHERE database_name = 'coworking_db'
  AND stat_name = 'size'
  AND index_name IN ('idx_reserva_estado_fecha',
                     'idx_reserva_espacio_inicio',
                     'idx_cuota_pago_monto');

-- Para repetir la prueba desde cero basta con volver a correr este
-- archivo: al principio borra los tres índices.
