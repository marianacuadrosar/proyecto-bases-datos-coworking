-- ============================================================
-- VERIFICACIÓN DE LOS DATOS DE PRUEBA
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Correr justo después de 02_datos_prueba.sql, antes de
-- 03_consultas.sql: esas consultas cambian una tarifa, confirman una
-- reserva y retiran un espacio, y eso altera tres reglas a propósito.
-- También se puede correr después de 04_datos_sinteticos.sql. Cada
-- fila es una regla del negocio; la columna violaciones debe dar 0.
--
-- La fecha de corte es fija (2026-11-16) para que el resultado no
-- cambie según el día en que se ejecute el script.
--
-- Si ya se corrió la consulta que actualiza una tarifa, la regla 9
-- marca las reservas hechas con el precio anterior. Eso es
-- lo esperado: tarifa_aplicada guarda el precio del momento.
-- ============================================================

USE coworking_db;

SET @corte = '2026-11-16';

-- 1. Cantidad de filas por tabla
SELECT 'sede' AS tabla, COUNT(*) AS filas FROM sede
UNION ALL SELECT 'tipo_espacio', COUNT(*) FROM tipo_espacio
UNION ALL SELECT 'modalidad', COUNT(*) FROM modalidad
UNION ALL SELECT 'espacio', COUNT(*) FROM espacio
UNION ALL SELECT 'tarifa', COUNT(*) FROM tarifa
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'persona_natural', COUNT(*) FROM persona_natural
UNION ALL SELECT 'empresa', COUNT(*) FROM empresa
UNION ALL SELECT 'telefono_cliente', COUNT(*) FROM telefono_cliente
UNION ALL SELECT 'reserva', COUNT(*) FROM reserva
UNION ALL SELECT 'reserva_espacio', COUNT(*) FROM reserva_espacio
UNION ALL SELECT 'cuota', COUNT(*) FROM cuota;

-- 2. Reglas del negocio
SELECT '01 Cliente en ninguna o en ambas subclases' AS regla, COUNT(*) AS violaciones
FROM cliente c
WHERE (EXISTS (SELECT 1 FROM persona_natural p WHERE p.cliente_id = c.cliente_id))
    = (EXISTS (SELECT 1 FROM empresa e WHERE e.cliente_id = c.cliente_id))

UNION ALL
SELECT '02 tipo_cliente no coincide con la subclase', COUNT(*)
FROM cliente c
WHERE (c.tipo_cliente = 'NATURAL'
       AND NOT EXISTS (SELECT 1 FROM persona_natural p WHERE p.cliente_id = c.cliente_id))
   OR (c.tipo_cliente = 'EMPRESA'
       AND NOT EXISTS (SELECT 1 FROM empresa e WHERE e.cliente_id = c.cliente_id))

UNION ALL
SELECT '03 Email repetido', COUNT(*)
FROM (SELECT email FROM cliente GROUP BY email HAVING COUNT(*) > 1) d

UNION ALL
SELECT '04 Reservas cruzadas sobre el mismo espacio', COUNT(*)
FROM reserva_espacio a
JOIN reserva_espacio b
  ON a.espacio_id = b.espacio_id
 AND a.reserva_id < b.reserva_id
 AND a.inicio < b.fin
 AND b.inicio < a.fin

UNION ALL
SELECT '05 Reserva fuera del horario de la sede', COUNT(*)
FROM reserva_espacio re
JOIN espacio e ON e.espacio_id = re.espacio_id
JOIN sede s ON s.sede_id = e.sede_id
WHERE DATE(re.inicio) <> DATE(re.fin)
   OR TIME(re.inicio) < s.hora_apertura
   OR TIME(re.fin) > s.hora_cierre

UNION ALL
SELECT '06 Reserva por día que no cubre apertura a cierre', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
JOIN espacio e ON e.espacio_id = re.espacio_id
JOIN sede s ON s.sede_id = e.sede_id
JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE m.nombre = 'Dia'
  AND (TIME(re.inicio) <> s.hora_apertura OR TIME(re.fin) <> s.hora_cierre)

UNION ALL
SELECT '07 Reserva con espacios de varias sedes', COUNT(*)
FROM (SELECT re.reserva_id
      FROM reserva_espacio re
      JOIN espacio e ON e.espacio_id = re.espacio_id
      GROUP BY re.reserva_id
      HAVING COUNT(DISTINCT e.sede_id) > 1) d

UNION ALL
SELECT '08 Espacio reservado sin tarifa para esa modalidad', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
JOIN espacio e ON e.espacio_id = re.espacio_id
WHERE NOT EXISTS (SELECT 1 FROM tarifa t
                  WHERE t.sede_id = e.sede_id
      AND t.tipo_id = e.tipo_id
      AND t.modalidad_id = r.modalidad_id)

UNION ALL
SELECT '09 tarifa_aplicada distinta de la tarifa vigente', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
JOIN espacio e ON e.espacio_id = re.espacio_id
JOIN tarifa t ON t.sede_id = e.sede_id
      AND t.tipo_id = e.tipo_id
      AND t.modalidad_id = r.modalidad_id
WHERE re.tarifa_aplicada <> t.valor

UNION ALL
SELECT '10 Cliente con reserva anterior a su registro', COUNT(*)
FROM reserva r
JOIN cliente c ON c.cliente_id = r.cliente_id
WHERE r.fecha_creacion < c.fecha_registro

UNION ALL
SELECT '11 Reserva creada después de la fecha de uso', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
WHERE r.fecha_creacion > DATE(re.inicio)

UNION ALL
SELECT '12 Estado no coincide con la fecha de uso', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
WHERE (r.estado = 'FINALIZADA' AND DATE(re.fin) >= @corte)
   OR (r.estado IN ('PENDIENTE', 'CONFIRMADA') AND DATE(re.fin) < @corte)

UNION ALL
SELECT '13 Reserva FINALIZADA sin cuotas o con cuotas sin pagar', COUNT(*)
FROM reserva r
WHERE r.estado = 'FINALIZADA'
  AND (NOT EXISTS (SELECT 1 FROM cuota q WHERE q.reserva_id = r.reserva_id)
       OR EXISTS (SELECT 1 FROM cuota q WHERE q.reserva_id = r.reserva_id AND q.fecha_pago IS NULL))

UNION ALL
SELECT '14 Cuotas que no suman el valor de la reserva', COUNT(*)
FROM (SELECT r.reserva_id,
             (SELECT SUM(q.monto) FROM cuota q WHERE q.reserva_id = r.reserva_id) AS cuotas,
             (SELECT SUM(re.tarifa_aplicada *
                         CASE WHEN m.nombre = 'Hora'
                              THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                              ELSE 1 END)
              FROM reserva_espacio re WHERE re.reserva_id = r.reserva_id) AS valor
      FROM reserva r
      JOIN modalidad m ON m.modalidad_id = r.modalidad_id
      WHERE EXISTS (SELECT 1 FROM cuota q WHERE q.reserva_id = r.reserva_id)) d
WHERE ABS(d.cuotas - d.valor) > 1

UNION ALL
SELECT '15 Cuota pagada en reserva PENDIENTE o CANCELADA', COUNT(*)
FROM cuota q
JOIN reserva r ON r.reserva_id = q.reserva_id
WHERE r.estado IN ('PENDIENTE', 'CANCELADA')
  AND q.fecha_pago IS NOT NULL

UNION ALL
SELECT '16 Reserva CONFIRMADA sin la primera cuota pagada', COUNT(*)
FROM reserva r
WHERE r.estado = 'CONFIRMADA'
  AND NOT EXISTS (SELECT 1 FROM cuota q
                  WHERE q.reserva_id = r.reserva_id
                    AND q.num_cuota = 1
                    AND q.fecha_pago IS NOT NULL)

UNION ALL
SELECT '17 Pago anterior a la creación o posterior al corte', COUNT(*)
FROM cuota q
JOIN reserva r ON r.reserva_id = q.reserva_id
WHERE q.fecha_pago < r.fecha_creacion
   OR q.fecha_pago > @corte

UNION ALL
SELECT '18 Pago registrado sin método o método sin pago', COUNT(*)
FROM cuota
WHERE (fecha_pago IS NULL) <> (metodo_pago IS NULL)

UNION ALL
SELECT '19 Persona menor de edad al registrarse', COUNT(*)
FROM persona_natural p
JOIN cliente c ON c.cliente_id = p.cliente_id
WHERE TIMESTAMPDIFF(YEAR, p.fecha_nacimiento, c.fecha_registro) < 18

UNION ALL
SELECT '20 Cabina telefónica reservada por día', COUNT(*)
FROM reserva r
JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
JOIN espacio e ON e.espacio_id = re.espacio_id
JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE te.nombre = 'Cabina telefónica' AND m.nombre = 'Dia';
