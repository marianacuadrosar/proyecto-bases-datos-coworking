-- ============================================================
-- VISTAS Y CONSULTAS CON UNION / UNION ALL
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: después de 07_procedimientos_funciones.sql, porque
-- la vista de reservas usa sus funciones fn_valor_reserva y
-- fn_saldo_pendiente. Se puede correr varias veces: las vistas usan
-- CREATE OR REPLACE.
--
-- Las tres vistas no son solo para reportes: la aplicación web las
-- consulta a través de los procedimientos de 11_procedimientos_app.sql.
-- Así la lógica para armar un cliente, un espacio o una reserva queda
-- escrita una sola vez, en la base de datos.
--
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;


-- ============================================================
-- VISTA 1 - vw_cliente_detalle
-- Ficha de cada cliente, sea persona natural o empresa
-- ============================================================

-- Pregunta de negocio:
-- ¿Quién es cada cliente, cómo se le contacta y cuántas reservas
-- ha hecho?
--
-- Justificación:
-- Los datos de un cliente están repartidos en cinco tablas: CLIENTE,
-- su subclase (PERSONA_NATURAL o EMPRESA), TELEFONO_CLIENTE y RESERVA.
-- La aplicación y los reportes necesitan esa ficha completa en muchos
-- lugares, así que una vista evita repetir el mismo JOIN en cada uno.
--
-- LEFT JOIN con las dos subclases porque cada cliente está en una sola:
-- con INNER JOIN no saldría ningún cliente. COALESCE toma el dato de la
-- subclase que sí existe.
--
-- Teléfonos y reservas se agrupan antes en subconsultas. Si se uniera
-- directo con TELEFONO_CLIENTE y RESERVA, un cliente con 2 teléfonos y
-- 3 reservas saldría en 6 filas y el conteo de reservas daría 6.

CREATE OR REPLACE VIEW vw_cliente_detalle AS
SELECT
    c.cliente_id,
    c.tipo_cliente,
    COALESCE(CONCAT(p.nombres, ' ', p.apellidos), e.razon_social) AS nombre,
    COALESCE(p.documento, e.nit) AS identificacion,
    e.nombre_contacto,
    c.email,
    c.fecha_registro,
    t.telefonos,
    COALESCE(r.total_reservas, 0) AS total_reservas
FROM cliente c
LEFT JOIN persona_natural p ON p.cliente_id = c.cliente_id
LEFT JOIN empresa e         ON e.cliente_id = c.cliente_id
LEFT JOIN (
    SELECT cliente_id,
           GROUP_CONCAT(telefono ORDER BY telefono SEPARATOR ', ') AS telefonos
    FROM telefono_cliente
    GROUP BY cliente_id
) t ON t.cliente_id = c.cliente_id
LEFT JOIN (
    SELECT cliente_id, COUNT(*) AS total_reservas
    FROM reserva
    GROUP BY cliente_id
) r ON r.cliente_id = c.cliente_id;

-- Prueba: los clientes que más han reservado.
SELECT cliente_id, tipo_cliente, nombre, identificacion, telefonos, total_reservas
FROM vw_cliente_detalle
ORDER BY total_reservas DESC, nombre
LIMIT 10;


-- ============================================================
-- VISTA 2 - vw_espacio_catalogo
-- Catálogo de espacios con su sede y sus precios
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué espacios ofrece la red, dónde están, para cuántas personas
-- son y cuánto cuestan por hora y por día?
--
-- Justificación:
-- Es lo primero que se consulta antes de reservar. El precio vive en
-- TARIFA, que depende de sede, tipo y modalidad a la vez (la relación
-- ternaria), así que hay que unir TARIFA dos veces: una para el precio
-- por hora y otra para el precio por día.
--
-- Esas dos uniones son LEFT JOIN porque no todas las combinaciones
-- existen. Las cabinas telefónicas no se alquilan por día: con INNER
-- JOIN desaparecerían del catálogo. Con LEFT JOIN salen con precio_dia
-- en NULL, que es justo lo que significa "no se ofrece".

CREATE OR REPLACE VIEW vw_espacio_catalogo AS
SELECT
    e.espacio_id,
    e.codigo,
    e.capacidad,
    s.sede_id,
    s.nombre  AS sede,
    s.ciudad,
    s.barrio,
    s.hora_apertura,
    s.hora_cierre,
    te.tipo_id,
    te.nombre AS tipo,
    th.valor  AS precio_hora,
    td.valor  AS precio_dia
FROM espacio e
INNER JOIN sede s          ON s.sede_id  = e.sede_id
INNER JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
LEFT JOIN modalidad mh     ON mh.nombre  = 'Hora'
LEFT JOIN modalidad md     ON md.nombre  = 'Dia'
LEFT JOIN tarifa th        ON th.sede_id = e.sede_id
                          AND th.tipo_id = e.tipo_id
                          AND th.modalidad_id = mh.modalidad_id
LEFT JOIN tarifa td        ON td.sede_id = e.sede_id
                          AND td.tipo_id = e.tipo_id
                          AND td.modalidad_id = md.modalidad_id;

-- Prueba: salas de reuniones de Medellín, de la más barata a la más cara.
SELECT sede, barrio, codigo, capacidad, precio_hora, precio_dia
FROM vw_espacio_catalogo
WHERE ciudad = 'Medellín' AND tipo = 'Sala de reuniones'
ORDER BY precio_hora, capacidad DESC;


-- ============================================================
-- VISTA 3 - vw_reserva_resumen
-- Una fila por reserva, con su valor total, lo pagado y el saldo
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuánto vale cada reserva, cuánto ha pagado el cliente y cuánto
-- le falta?
--
-- Justificación:
-- valor_total es el atributo derivado del diagrama E/R: no se guarda
-- en ninguna tabla. La vista no repite su fórmula: usa las funciones
-- fn_valor_reserva y fn_saldo_pendiente de 07_procedimientos_funciones.sql,
-- así el valor de una reserva se calcula igual en la vista, en los
-- procedimientos y en los reportes. Una reserva cancelada no se cobra,
-- por eso fn_saldo_pendiente le da saldo 0.
--
-- La sede, el número de espacios y el horario se agrupan en una
-- subconsulta y lo pagado en otra, y después se unen por reserva_id.
-- Si se uniera RESERVA_ESPACIO con CUOTA directamente, cada cuota se
-- repetiría una vez por espacio y lo pagado saldría multiplicado.
--
-- Las dos subconsultas van con LEFT JOIN para que una reserva sin
-- espacios o sin pagos siga apareciendo, con 0 en vez de desaparecer.

CREATE OR REPLACE VIEW vw_reserva_resumen AS
SELECT
    r.reserva_id,
    r.fecha_creacion,
    r.estado,
    m.nombre AS modalidad,
    r.cliente_id,
    COALESCE(CONCAT(p.nombres, ' ', p.apellidos), em.razon_social) AS cliente,
    l.sede,
    l.ciudad,
    COALESCE(l.espacios, 0) AS espacios,
    l.inicio,
    l.fin,
    COALESCE(fn_valor_reserva(r.reserva_id), 0) AS valor_total,
    COALESCE(q.pagado, 0) AS pagado,
    fn_saldo_pendiente(r.reserva_id) AS saldo
FROM reserva r
INNER JOIN modalidad m       ON m.modalidad_id = r.modalidad_id
LEFT JOIN persona_natural p  ON p.cliente_id   = r.cliente_id
LEFT JOIN empresa em         ON em.cliente_id  = r.cliente_id
LEFT JOIN (
    SELECT re.reserva_id,
           MIN(s.nombre) AS sede,
           MIN(s.ciudad) AS ciudad,
           COUNT(*)      AS espacios,
           MIN(re.inicio) AS inicio,
           MAX(re.fin)    AS fin
    FROM reserva_espacio re
    INNER JOIN espacio e    ON e.espacio_id    = re.espacio_id
    INNER JOIN sede s       ON s.sede_id       = e.sede_id
    GROUP BY re.reserva_id
) l ON l.reserva_id = r.reserva_id
LEFT JOIN (
    SELECT reserva_id, SUM(monto) AS pagado
    FROM cuota
    WHERE fecha_pago IS NOT NULL
    GROUP BY reserva_id
) q ON q.reserva_id = r.reserva_id;

-- Prueba: reservas vigentes con saldo pendiente, de la que más debe a la que menos.
SELECT reserva_id, estado, cliente, sede, inicio, valor_total, pagado, saldo
FROM vw_reserva_resumen
WHERE estado IN ('PENDIENTE', 'CONFIRMADA') AND saldo > 0
ORDER BY saldo DESC;


-- ============================================================
-- CONSULTA UNION 1 - UNION ALL
-- Estado de cuenta de un cliente
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué movimientos tuvo en 2026 el cliente 2 (Tequendama Ingeniería
-- S.A.S.): cuánto se le cobró por reservas y cuánto abonó?
--
-- Justificación:
-- Un estado de cuenta mezcla dos cosas que viven en tablas distintas:
-- los cargos salen de las reservas (vw_reserva_resumen) y los abonos
-- de las cuotas pagadas (CUOTA). Las dos consultas devuelven las mismas
-- columnas, así que UNION las pone una debajo de la otra en una sola
-- lista ordenada por fecha. Un JOIN no sirve: pondría cargos y abonos
-- lado a lado y repetiría cada cargo por cada pago.
--
-- Se usa UNION ALL y no UNION porque en un estado de cuenta ningún
-- movimiento se puede perder. Si el cliente hiciera dos abonos iguales
-- el mismo día, UNION los fundiría en uno y el saldo quedaría mal.
-- Además UNION ALL no tiene que buscar duplicados, así que es más rápido.
--
-- Los abonos van en negativo para que la suma de la columna valor sea
-- el saldo del cliente.

SELECT r.fecha_creacion AS fecha,
       'Cargo' AS movimiento,
       CONCAT('Reserva ', r.reserva_id, ' por ', r.modalidad, ' en ', r.sede) AS detalle,
       r.valor_total AS valor
FROM vw_reserva_resumen r
WHERE r.cliente_id = 2
  AND r.estado <> 'CANCELADA'
  AND r.fecha_creacion >= '2026-01-01'

UNION ALL

SELECT q.fecha_pago,
       'Abono',
       CONCAT('Cuota ', q.num_cuota, ' de la reserva ', q.reserva_id, ' (', q.metodo_pago, ')'),
       -q.monto
FROM cuota q
INNER JOIN reserva r ON r.reserva_id = q.reserva_id
WHERE r.cliente_id = 2
  AND r.estado <> 'CANCELADA'
  AND r.fecha_creacion >= '2026-01-01'
  AND q.fecha_pago IS NOT NULL

ORDER BY fecha, movimiento DESC;


-- ============================================================
-- CONSULTA UNION 2 - UNION ALL
-- Recaudado y por cobrar, mes a mes
-- ============================================================

-- Pregunta de negocio:
-- En cada mes de 2026, ¿cuánto dinero entró de verdad y cuánto
-- quedó pendiente de cobrar en reservas vigentes?
--
-- Justificación:
-- Son dos cálculos con filtros opuestos sobre la misma tabla: lo
-- recaudado son las cuotas con fecha_pago, agrupadas por el mes del
-- pago; lo pendiente son las cuotas sin pagar de reservas vigentes,
-- agrupadas por el mes en que se creó la reserva, porque no tienen
-- fecha de pago. Como cada parte agrupa por una fecha distinta, no
-- caben en un solo GROUP BY. UNION ALL junta los dos resultados y la
-- columna concepto dice de cuál viene cada fila.
--
-- UNION ALL porque las filas de las dos partes nunca son iguales
-- (cambia el concepto), así que buscar duplicados con UNION sería
-- trabajo perdido.

SELECT DATE_FORMAT(q.fecha_pago, '%Y-%m') AS mes,
       'Recaudado' AS concepto,
       COUNT(*)     AS cuotas,
       SUM(q.monto) AS total
FROM cuota q
WHERE q.fecha_pago >= '2026-01-01' AND q.fecha_pago < '2027-01-01'
GROUP BY DATE_FORMAT(q.fecha_pago, '%Y-%m')

UNION ALL

SELECT DATE_FORMAT(r.fecha_creacion, '%Y-%m'),
       'Por cobrar',
       COUNT(*),
       SUM(q.monto)
FROM cuota q
INNER JOIN reserva r ON r.reserva_id = q.reserva_id
WHERE q.fecha_pago IS NULL
  AND r.estado IN ('PENDIENTE', 'CONFIRMADA')
  AND r.fecha_creacion >= '2026-01-01' AND r.fecha_creacion < '2027-01-01'
GROUP BY DATE_FORMAT(r.fecha_creacion, '%Y-%m')

ORDER BY mes, concepto DESC;


-- ============================================================
-- CONSULTA UNION 3 - UNION
-- Clientes a contactar esta semana
-- ============================================================

-- Pregunta de negocio:
-- ¿A qué clientes tiene que llamar el equipo comercial en la semana
-- del 16 al 22 de noviembre de 2026, ya sea para cobrar un saldo o
-- para recordarles una reserva que empieza esos días?
--
-- Justificación:
-- Son dos listas con criterios distintos: clientes con cuotas sin
-- pagar en reservas vigentes, y clientes con una reserva confirmada o
-- pendiente que empieza esa semana. Hay que unirlas, y un mismo
-- cliente puede estar en las dos.
--
-- Aquí sí se usa UNION y no UNION ALL: la idea es hacer una sola
-- llamada por cliente, así que los repetidos sobran. UNION también
-- quita los repetidos dentro de cada parte, por ejemplo un cliente con
-- tres cuotas pendientes.
--
-- Por eso las dos partes no tienen una columna "motivo": si la
-- tuvieran, la fila de cobro y la de recordatorio del mismo cliente
-- serían distintas y UNION ya no las juntaría.

SELECT d.cliente_id, d.nombre, d.tipo_cliente, d.email, d.telefonos
FROM cuota q
INNER JOIN reserva r            ON r.reserva_id = q.reserva_id
INNER JOIN vw_cliente_detalle d ON d.cliente_id = r.cliente_id
WHERE q.fecha_pago IS NULL
  AND r.estado IN ('PENDIENTE', 'CONFIRMADA')

UNION

SELECT d.cliente_id, d.nombre, d.tipo_cliente, d.email, d.telefonos
FROM reserva r
INNER JOIN reserva_espacio re   ON re.reserva_id = r.reserva_id
INNER JOIN vw_cliente_detalle d ON d.cliente_id = r.cliente_id
WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
  AND re.inicio >= '2026-11-16' AND re.inicio < '2026-11-23'

ORDER BY nombre;
