-- ============================================================
-- CONSULTAS DE ANÁLISIS
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Requiere 02_datos_prueba.sql. Funcionan igual con o sin
-- 04_datos_sinteticos.sql: las que hablan de 2025 o 2026 filtran por
-- fecha, y el histórico sintético es de 2023 y 2024.
--
-- Valor de una reserva: cada fila de reserva_espacio vale
-- tarifa_aplicada x horas (modalidad Hora) o tarifa_aplicada x 1
-- (modalidad Dia). Varias consultas repiten ese cálculo.
-- ============================================================

USE coworking_db;


-- ============================================================
-- CONSULTA 1 - INNER JOIN
-- Agenda de reservas confirmadas de empresas
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué empresas tienen reservas confirmadas, en qué sede y espacio,
-- y a qué hora deben estar listos?
--
-- Justificación:
-- Los datos están en seis tablas: el estado en RESERVA, el nombre en
-- EMPRESA, el horario en RESERVA_ESPACIO, el código en ESPACIO, el tipo
-- en TIPO_ESPACIO y la dirección en SEDE. INNER JOIN con EMPRESA deja
-- por fuera a las personas naturales sin escribir un filtro adicional,
-- porque solo las empresas tienen fila en esa tabla.

SELECT r.reserva_id, em.razon_social, em.nombre_contacto, s.nombre AS sede,
       s.ciudad, e.codigo AS espacio, te.nombre AS tipo_espacio, re.inicio, re.fin
FROM reserva r
INNER JOIN empresa em ON em.cliente_id = r.cliente_id
INNER JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
INNER JOIN espacio e ON e.espacio_id = re.espacio_id
INNER JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
INNER JOIN sede s ON s.sede_id = e.sede_id
WHERE r.estado = 'CONFIRMADA'
ORDER BY re.inicio, s.nombre, e.codigo;


-- ============================================================
-- CONSULTA 2 - INNER JOIN
-- Pagos de personas naturales entre agosto y octubre de 2026
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué pagos hicieron las personas naturales entre agosto y octubre
-- de 2026, por cuánto y con qué medio de pago?
--
-- Justificación:
-- CUOTA tiene el monto y la fecha, pero no dice quién pagó. Hay que
-- pasar por RESERVA para llegar al cliente y por PERSONA_NATURAL para
-- obtener el nombre y el documento. INNER JOIN descarta las cuotas de
-- empresas y las que no tienen pago, porque fecha_pago en NULL no
-- cumple el BETWEEN.

SELECT q.fecha_pago, CONCAT(p.nombres, ' ', p.apellidos) AS cliente, p.documento,
       q.reserva_id, q.num_cuota, q.monto, q.metodo_pago
FROM cuota q
INNER JOIN reserva r ON r.reserva_id = q.reserva_id
INNER JOIN persona_natural p ON p.cliente_id = r.cliente_id
WHERE q.fecha_pago BETWEEN '2026-08-01' AND '2026-10-31'
ORDER BY q.fecha_pago, q.reserva_id, q.num_cuota;


-- ============================================================
-- CONSULTA 3 - INNER JOIN
-- Precio por hora de las salas de reuniones en Bogotá
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuánto cuesta la hora de sala de reuniones en cada sede de Bogotá
-- y para cuántas personas es cada sala?
--
-- Justificación:
-- El precio no está en ESPACIO sino en TARIFA, que depende de la sede,
-- el tipo y la modalidad a la vez. Por eso el JOIN con TARIFA usa dos
-- columnas del espacio (sede_id y tipo_id) y MODALIDAD fija la tercera.
-- Una sala sin tarifa por hora no aparecería, y eso también es
-- información: no se puede alquilar por hora.

SELECT s.nombre AS sede, s.barrio, e.codigo AS sala, e.capacidad,
       t.valor AS precio_hora
FROM espacio e
INNER JOIN sede s ON s.sede_id = e.sede_id
INNER JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
INNER JOIN tarifa t ON t.sede_id = e.sede_id
      AND t.tipo_id = e.tipo_id
INNER JOIN modalidad m ON m.modalidad_id = t.modalidad_id
WHERE s.ciudad = 'Bogotá' AND te.nombre = 'Sala de reuniones' AND m.nombre = 'Hora'
ORDER BY t.valor DESC, e.capacidad DESC, s.nombre;


-- ============================================================
-- CONSULTA 4 - FUNCIONES DE AGREGACIÓN
-- Recaudo de 2026
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuánto dinero ha recibido la red en 2026, en cuántos pagos, y
-- cuáles fueron el pago promedio, el más pequeño y el más grande?
--
-- Justificación:
-- COUNT, SUM, AVG, MIN y MAX resumen todas las cuotas pagadas en una
-- sola fila. No hay GROUP BY porque la pregunta es sobre la red
-- completa, no por sede ni por cliente.

SELECT COUNT(*) AS pagos, SUM(q.monto) AS total_recaudado,
       ROUND(AVG(q.monto)) AS pago_promedio, MIN(q.monto) AS pago_minimo,
       MAX(q.monto) AS pago_maximo
FROM cuota q
WHERE q.fecha_pago BETWEEN '2026-01-01' AND '2026-12-31';


-- ============================================================
-- CONSULTA 5 - FUNCIONES DE AGREGACIÓN
-- Cartera por cobrar
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuánto dinero falta por cobrar en reservas que siguen vigentes,
-- cuántas reservas y cuántos clientes lo deben?
--
-- Justificación:
-- Se cuentan solo cuotas sin pagar de reservas PENDIENTES o
-- CONFIRMADAS; las de reservas canceladas no se van a cobrar.
-- COUNT(DISTINCT ...) evita contar dos veces la misma reserva o el
-- mismo cliente cuando tienen varias cuotas pendientes.

SELECT COUNT(*) AS cuotas_pendientes, COUNT(DISTINCT q.reserva_id) AS reservas,
       COUNT(DISTINCT r.cliente_id) AS clientes, SUM(q.monto) AS total_por_cobrar,
       MAX(q.monto) AS cuota_mas_alta
FROM cuota q
INNER JOIN reserva r ON r.reserva_id = q.reserva_id
WHERE q.fecha_pago IS NULL AND r.estado IN ('PENDIENTE', 'CONFIRMADA');


-- ============================================================
-- CONSULTA 6 - FUNCIONES DE AGREGACIÓN
-- Duración de las reservas por hora
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuántas horas dura en promedio una reserva por hora, cuál es la
-- más corta y cuál la más larga, en 2025 y 2026?
--
-- Justificación:
-- TIMESTAMPDIFF calcula los minutos de cada fila y AVG, MIN y MAX los
-- resumen. Sirve para decidir si conviene vender paquetes de 2 o
-- 4 horas. Se excluyen las canceladas porque no se usaron.

SELECT COUNT(*) AS reservas_por_hora,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, re.inicio, re.fin)) / 60, 2) AS horas_promedio,
       ROUND(MIN(TIMESTAMPDIFF(MINUTE, re.inicio, re.fin)) / 60, 2) AS horas_minimo,
       ROUND(MAX(TIMESTAMPDIFF(MINUTE, re.inicio, re.fin)) / 60, 2) AS horas_maximo,
       ROUND(SUM(TIMESTAMPDIFF(MINUTE, re.inicio, re.fin)) / 60, 2) AS horas_totales
FROM reserva_espacio re
INNER JOIN reserva r ON r.reserva_id = re.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE m.nombre = 'Hora' AND r.estado <> 'CANCELADA' AND re.inicio >= '2025-01-01';


-- ============================================================
-- CONSULTA 7 - GROUP BY
-- Facturación por ciudad en 2026
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuánto facturó cada ciudad en 2026 por reservas finalizadas?
--
-- Justificación:
-- GROUP BY ciudad suma el valor de cada fila de RESERVA_ESPACIO.
-- Se suma por fila y no por cuota porque una reserva puede tener
-- varios espacios; unir CUOTA con RESERVA_ESPACIO repetiría cada
-- cuota una vez por espacio y el total quedaría inflado.

SELECT s.ciudad, COUNT(DISTINCT r.reserva_id) AS reservas,
       ROUND(SUM(re.tarifa_aplicada * CASE WHEN m.nombre = 'Hora'
             THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
             ELSE 1 END)) AS facturado
FROM reserva r
INNER JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
INNER JOIN espacio e ON e.espacio_id = re.espacio_id
INNER JOIN sede s ON s.sede_id = e.sede_id
WHERE r.estado = 'FINALIZADA'
  AND re.inicio >= '2026-01-01' AND re.inicio < '2027-01-01'
GROUP BY s.ciudad
ORDER BY facturado DESC;


-- ============================================================
-- CONSULTA 8 - GROUP BY
-- Reservas por tipo de espacio y modalidad
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué tipos de espacio se reservan más, y se piden más por hora o
-- por día?
--
-- Justificación:
-- Agrupar por dos columnas da una fila por cada combinación de tipo
-- y modalidad. Así se ve, por ejemplo, que las salas se alquilan casi
-- siempre por hora y los escritorios se reparten entre las dos. Se
-- cuentan filas de RESERVA_ESPACIO porque cada una es un espacio
-- ocupado.

SELECT te.nombre AS tipo_espacio, m.nombre AS modalidad, COUNT(*) AS veces_reservado
FROM reserva_espacio re
INNER JOIN reserva r ON r.reserva_id = re.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
INNER JOIN espacio e ON e.espacio_id = re.espacio_id
INNER JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
WHERE r.estado <> 'CANCELADA' AND re.inicio >= '2025-01-01'
GROUP BY te.nombre, m.nombre
ORDER BY te.nombre, m.nombre;


-- ============================================================
-- CONSULTA 9 - GROUP BY
-- Reservas y valor reservado por mes en 2026
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo evolucionan mes a mes las reservas y el valor reservado
-- durante 2026?
--
-- Justificación:
-- DATE_FORMAT convierte la fecha de uso en 'AAAA-MM' y GROUP BY
-- agrupa por ese valor. Incluye reservas finalizadas, confirmadas y
-- pendientes porque la pregunta es por la demanda, no por el dinero
-- ya cobrado. Esta consulta filtra por rango de fechas sobre
-- re.inicio; es una de las que mejora con el índice
-- idx_reserva_espacio_inicio (ver 05_indices.sql).

SELECT DATE_FORMAT(re.inicio, '%Y-%m') AS mes,
       COUNT(DISTINCT r.reserva_id) AS reservas,
       ROUND(SUM(re.tarifa_aplicada * CASE WHEN m.nombre = 'Hora'
             THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
             ELSE 1 END)) AS valor_reservado
FROM reserva_espacio re
INNER JOIN reserva r ON r.reserva_id = re.reserva_id
INNER JOIN modalidad m ON m.modalidad_id = r.modalidad_id
WHERE r.estado <> 'CANCELADA'
  AND re.inicio >= '2026-01-01' AND re.inicio < '2027-01-01'
GROUP BY mes
ORDER BY mes;


-- ============================================================
-- CONSULTA 10 - HAVING
-- Clientes frecuentes
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué clientes han hecho cuatro o más reservas desde 2025, sin
-- contar las canceladas? Son candidatos a un plan de fidelización.
--
-- Justificación:
-- WHERE filtra filas antes de agrupar (fecha y estado) y HAVING
-- filtra grupos después de contar. La condición COUNT(*) >= 4 no
-- puede ir en WHERE porque el conteo solo existe después del
-- GROUP BY.

SELECT c.cliente_id, c.email, c.tipo_cliente, COUNT(*) AS reservas,
       MIN(r.fecha_creacion) AS primera, MAX(r.fecha_creacion) AS ultima
FROM reserva r
INNER JOIN cliente c ON c.cliente_id = r.cliente_id
WHERE r.estado <> 'CANCELADA' AND r.fecha_creacion >= '2025-01-01'
GROUP BY c.cliente_id, c.email, c.tipo_cliente
HAVING COUNT(*) >= 4
ORDER BY reservas DESC, c.cliente_id;


-- ============================================================
-- CONSULTA 11 - HAVING
-- Sedes con muchas cancelaciones
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué sedes tienen al menos cinco reservas desde 2025 y una de cada
-- cinco o más termina cancelada?
--
-- Justificación:
-- HAVING aplica dos condiciones al grupo: un mínimo de reservas, para
-- que el porcentaje no salga de dos o tres casos, y la proporción de
-- canceladas. COUNT(DISTINCT ...) cuenta reservas y no espacios,
-- porque una reserva con tres espacios es una sola cancelación.

SELECT s.nombre AS sede, s.ciudad, COUNT(DISTINCT r.reserva_id) AS reservas,
       COUNT(DISTINCT CASE WHEN r.estado = 'CANCELADA'
             THEN r.reserva_id END) AS canceladas,
       ROUND(100 * COUNT(DISTINCT CASE WHEN r.estado = 'CANCELADA'
             THEN r.reserva_id END)
             / COUNT(DISTINCT r.reserva_id), 1) AS porcentaje_cancelacion
FROM reserva r
INNER JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
INNER JOIN espacio e ON e.espacio_id = re.espacio_id
INNER JOIN sede s ON s.sede_id = e.sede_id
WHERE re.inicio >= '2025-01-01'
GROUP BY s.sede_id, s.nombre, s.ciudad
HAVING COUNT(DISTINCT r.reserva_id) >= 5
   AND COUNT(DISTINCT CASE WHEN r.estado = 'CANCELADA' THEN r.reserva_id END)
       >= 0.2 * COUNT(DISTINCT r.reserva_id)
ORDER BY porcentaje_cancelacion DESC, reservas DESC;


-- ============================================================
-- CONSULTA 12 - HAVING
-- Clientes que deben más de 250.000 pesos
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué clientes deben más de 250.000 pesos en cuotas de reservas
-- vigentes, y desde cuándo tienen reservas creadas sin pagar?
--
-- Justificación:
-- GROUP BY junta todas las cuotas pendientes de cada cliente y
-- HAVING SUM(...) > 250000 deja solo a los que superan el monto.
-- Es la lista que usaría el área de cobranza para llamar primero.

SELECT c.cliente_id, c.email, c.tipo_cliente, COUNT(*) AS cuotas_pendientes,
       SUM(q.monto) AS saldo, MIN(r.fecha_creacion) AS reserva_mas_antigua
FROM cuota q
INNER JOIN reserva r ON r.reserva_id = q.reserva_id
INNER JOIN cliente c ON c.cliente_id = r.cliente_id
WHERE q.fecha_pago IS NULL AND r.estado IN ('PENDIENTE', 'CONFIRMADA')
GROUP BY c.cliente_id, c.email, c.tipo_cliente
HAVING SUM(q.monto) > 250000
ORDER BY saldo DESC;
