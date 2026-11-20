-- ============================================================
-- BANCO DE CONSULTAS: SUBCONSULTAS, LEFT / RIGHT JOIN Y SELF JOIN
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: después de 02_datos_prueba.sql. Funciona igual
-- si antes se corrieron los demás scripts. Solo lee datos.
--
-- Contenido:
--   1 a 3    subconsulta en WHERE
--   4 a 6    subconsulta en FROM
--   7 a 9    LEFT JOIN o RIGHT JOIN
--   10 a 12  SELF JOIN
--
-- Valor de una línea de reserva (la misma regla de 06_consultas_analisis.sql):
-- tarifa_aplicada x horas si la modalidad es Hora, o x 1 si es Dia.
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;


-- ============================================================
-- CONSULTA 1 - SUBCONSULTA EN WHERE (NOT IN)
-- Espacios que no se han reservado desde 2025
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué espacios no han tenido ninguna reserva desde enero de 2025?
-- Son candidatos a una promoción o a cambiarles el uso.
--
-- Justificación:
-- La pregunta es "lo que NO aparece en otra tabla". La subconsulta arma
-- la lista de espacios que sí se reservaron y NOT IN deja los demás.
-- Un INNER JOIN no sirve, porque solo devuelve lo que sí tiene pareja.
-- NOT IN es seguro aquí porque espacio_id nunca es NULL en
-- reserva_espacio (es parte de su llave primaria): con un NULL en la
-- lista, NOT IN no devolvería ninguna fila.

SELECT e.espacio_id, e.codigo, te.nombre AS tipo, s.nombre AS sede, s.ciudad, e.capacidad
FROM espacio e
INNER JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
INNER JOIN sede s          ON s.sede_id  = e.sede_id
WHERE e.espacio_id NOT IN (
    SELECT re.espacio_id
    FROM reserva_espacio re
    WHERE re.inicio >= '2025-01-01'
)
ORDER BY s.ciudad, s.nombre, te.nombre, e.codigo;


-- ============================================================
-- CONSULTA 2 - SUBCONSULTA EN WHERE (correlacionada)
-- Sedes que cobran más que el promedio de la red
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué sedes cobran por encima del promedio de la red por el mismo
-- tipo de espacio y la misma modalidad? Sirve para revisar si esos
-- precios se justifican o están espantando clientes.
--
-- Justificación:
-- Cada tarifa se compara con el promedio de su propio grupo (mismo tipo
-- y misma modalidad), no con un promedio general: una sala de reuniones
-- no se compara con un escritorio. Por eso la subconsulta es
-- correlacionada: usa t.tipo_id y t.modalidad_id de la fila de afuera y
-- se recalcula para cada tarifa. AVG no puede ir directo en el WHERE.

SELECT s.nombre AS sede, s.ciudad, te.nombre AS tipo, m.nombre AS modalidad,
       t.valor,
       ROUND((SELECT AVG(t2.valor)
              FROM tarifa t2
              WHERE t2.tipo_id = t.tipo_id
                AND t2.modalidad_id = t.modalidad_id)) AS promedio_red
FROM tarifa t
INNER JOIN sede s          ON s.sede_id       = t.sede_id
INNER JOIN tipo_espacio te ON te.tipo_id      = t.tipo_id
INNER JOIN modalidad m     ON m.modalidad_id  = t.modalidad_id
WHERE te.nombre = 'Sala de reuniones'
  AND t.valor > (SELECT AVG(t2.valor)
                 FROM tarifa t2
                 WHERE t2.tipo_id = t.tipo_id
                   AND t2.modalidad_id = t.modalidad_id)
ORDER BY m.nombre, t.valor DESC;


-- ============================================================
-- CONSULTA 3 - SUBCONSULTA EN WHERE (IN)
-- Personas naturales que alquilan salas de reuniones
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué personas naturales han reservado al menos una sala de reuniones?
-- Las salas suelen ser de empresas: estas personas podrían interesarse
-- en un plan de emprendedor.
--
-- Justificación:
-- Con un JOIN directo cada persona saldría una vez por cada sala que
-- reservó y habría que agregar DISTINCT. Con IN la subconsulta solo
-- responde "¿este cliente está en la lista?", así que cada persona sale
-- una vez y la consulta de afuera se queda con las columnas de la
-- persona, sin traer las de la reserva.

SELECT p.cliente_id, p.nombres, p.apellidos, p.documento, c.email
FROM persona_natural p
INNER JOIN cliente c ON c.cliente_id = p.cliente_id
WHERE p.cliente_id IN (
    SELECT r.cliente_id
    FROM reserva r
    INNER JOIN reserva_espacio re ON re.reserva_id = r.reserva_id
    INNER JOIN espacio e          ON e.espacio_id  = re.espacio_id
    INNER JOIN tipo_espacio te    ON te.tipo_id    = e.tipo_id
    WHERE te.nombre = 'Sala de reuniones'
      AND r.estado <> 'CANCELADA'
)
ORDER BY p.apellidos, p.nombres;


-- ============================================================
-- CONSULTA 4 - SUBCONSULTA EN FROM
-- Reservas promedio por cliente, según el tipo de cliente
-- ============================================================

-- Pregunta de negocio:
-- En promedio, ¿cuántas reservas hace una persona natural y cuántas una
-- empresa? ¿Cuál es el máximo en cada grupo?
--
-- Justificación:
-- Son dos agregaciones, una encima de la otra: primero contar las
-- reservas de cada cliente y después promediar esos conteos por tipo.
-- SQL no permite AVG(COUNT(*)), así que el conteo por cliente se hace en
-- una subconsulta en FROM (una tabla derivada) y la consulta de afuera
-- la trata como una tabla más. Solo cuentan los clientes que ya
-- reservaron; los que no, están en la consulta 8.

SELECT c.tipo_cliente,
       COUNT(*)                    AS clientes,
       ROUND(AVG(x.reservas), 2)   AS reservas_promedio,
       MAX(x.reservas)             AS reservas_maximo
FROM (
    SELECT cliente_id, COUNT(*) AS reservas
    FROM reserva
    WHERE estado <> 'CANCELADA'
      AND fecha_creacion >= '2025-01-01'
    GROUP BY cliente_id
) x
INNER JOIN cliente c ON c.cliente_id = x.cliente_id
GROUP BY c.tipo_cliente;


-- ============================================================
-- CONSULTA 5 - SUBCONSULTA EN FROM
-- Valor promedio de una reserva en cada sede
-- ============================================================

-- Pregunta de negocio:
-- ¿En qué sedes deja más dinero cada reserva, en promedio? Las diez
-- primeras, contando todas las reservas finalizadas (también el
-- histórico 2023-2024) y solo sedes con al menos 10, para que el
-- promedio no salga de dos o tres casos.
--
-- Justificación:
-- Una reserva puede tener varios espacios, así que su valor es la suma
-- de sus líneas. Si se promediara directo sobre RESERVA_ESPACIO, se
-- obtendría el valor promedio de una línea, no de una reserva. La
-- subconsulta en FROM primero suma el valor de cada reserva y la de
-- afuera promedia esas sumas por sede.

SELECT v.sede, v.ciudad,
       COUNT(*)              AS reservas,
       ROUND(AVG(v.valor))   AS valor_promedio,
       ROUND(SUM(v.valor))   AS facturado
FROM (
    SELECT r.reserva_id, s.nombre AS sede, s.ciudad,
           SUM(re.tarifa_aplicada *
               CASE WHEN m.nombre = 'Hora'
                    THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                    ELSE 1 END) AS valor
    FROM reserva r
    INNER JOIN modalidad m        ON m.modalidad_id = r.modalidad_id
    INNER JOIN reserva_espacio re ON re.reserva_id  = r.reserva_id
    INNER JOIN espacio e          ON e.espacio_id   = re.espacio_id
    INNER JOIN sede s             ON s.sede_id      = e.sede_id
    WHERE r.estado = 'FINALIZADA'
    GROUP BY r.reserva_id, s.nombre, s.ciudad
) v
GROUP BY v.sede, v.ciudad
HAVING COUNT(*) >= 10
ORDER BY valor_promedio DESC
LIMIT 10;


-- ============================================================
-- CONSULTA 6 - SUBCONSULTA EN FROM (dos tablas derivadas)
-- El cliente que más ha pagado dentro de cada tipo
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuál es la persona natural que más ha pagado y cuál la empresa?
-- Son los clientes a cuidar con un trato preferencial.
--
-- Justificación:
-- Hacen falta dos resultados intermedios: lo que pagó cada cliente
-- (tabla derivada p) y el máximo pagado en cada tipo (tabla derivada
-- mx, que se calcula a partir de p). Al unirlas por tipo y monto quedan
-- solo los clientes que alcanzan el máximo de su grupo. Con un solo
-- GROUP BY no se puede, porque el máximo de cada grupo y el cliente que
-- lo tiene están en niveles de agregación distintos.

SELECT p.tipo_cliente, p.cliente_id, c.email, p.total_pagado
FROM (
    SELECT c.cliente_id, c.tipo_cliente, SUM(q.monto) AS total_pagado
    FROM cuota q
    INNER JOIN reserva r ON r.reserva_id = q.reserva_id
    INNER JOIN cliente c ON c.cliente_id = r.cliente_id
    WHERE q.fecha_pago >= '2025-01-01'
    GROUP BY c.cliente_id, c.tipo_cliente
) p
INNER JOIN (
    SELECT tipo_cliente, MAX(total_pagado) AS maximo
    FROM (
        SELECT c.cliente_id, c.tipo_cliente, SUM(q.monto) AS total_pagado
        FROM cuota q
        INNER JOIN reserva r ON r.reserva_id = q.reserva_id
        INNER JOIN cliente c ON c.cliente_id = r.cliente_id
        WHERE q.fecha_pago >= '2025-01-01'
        GROUP BY c.cliente_id, c.tipo_cliente
    ) t
    GROUP BY tipo_cliente
) mx ON mx.tipo_cliente = p.tipo_cliente AND mx.maximo = p.total_pagado
INNER JOIN cliente c ON c.cliente_id = p.cliente_id
ORDER BY p.tipo_cliente;


-- ============================================================
-- CONSULTA 7 - LEFT JOIN
-- Reservas de 2026 en cada sede, incluidas las sedes sin reservas
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuántas reservas no canceladas tuvo cada sede en 2026? Las sedes que
-- no tuvieron ninguna también deben salir, con 0, porque son las que
-- más preocupan.
--
-- Justificación:
-- Con INNER JOIN las sedes sin reservas desaparecerían del reporte.
-- LEFT JOIN conserva todas las filas de SEDE y pone NULL donde no hay
-- reserva; COUNT(DISTINCT r.reserva_id) no cuenta los NULL, así que esas
-- sedes salen con 0.
--
-- Detalle importante: el filtro de año y de estado va en el ON y no en
-- el WHERE. Si fuera en el WHERE, las filas con NULL no lo cumplirían y
-- el LEFT JOIN se comportaría como un INNER JOIN.

SELECT s.nombre AS sede, s.ciudad,
       COUNT(DISTINCT e.espacio_id) AS espacios,
       COUNT(DISTINCT r.reserva_id) AS reservas_2026
FROM sede s
LEFT JOIN espacio e          ON e.sede_id     = s.sede_id
LEFT JOIN reserva_espacio re ON re.espacio_id = e.espacio_id
                            AND re.inicio >= '2026-01-01'
                            AND re.inicio <  '2027-01-01'
LEFT JOIN reserva r          ON r.reserva_id  = re.reserva_id
                            AND r.estado <> 'CANCELADA'
GROUP BY s.sede_id, s.nombre, s.ciudad
ORDER BY reservas_2026, s.ciudad, s.nombre;


-- ============================================================
-- CONSULTA 8 - LEFT JOIN
-- Clientes registrados que nunca han reservado
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué clientes se registraron pero nunca han hecho una reserva? Son la
-- lista para una campaña de primera reserva.
--
-- Justificación:
-- LEFT JOIN trae todos los clientes y, a los que no tienen reserva, les
-- pone NULL en las columnas de RESERVA. El WHERE r.reserva_id IS NULL
-- se queda justo con esos. Es el patrón "anti-join": la misma pregunta
-- que la consulta 1, resuelta con JOIN en vez de subconsulta. Aquí el
-- filtro sí va en el WHERE, porque lo que se busca es la fila vacía.
--
-- Los LEFT JOIN con las subclases traen el nombre de quien corresponda.

SELECT c.cliente_id, c.tipo_cliente,
       COALESCE(CONCAT(p.nombres, ' ', p.apellidos), em.razon_social) AS nombre,
       c.email, c.fecha_registro
FROM cliente c
LEFT JOIN reserva r          ON r.cliente_id  = c.cliente_id
LEFT JOIN persona_natural p  ON p.cliente_id  = c.cliente_id
LEFT JOIN empresa em         ON em.cliente_id = c.cliente_id
WHERE r.reserva_id IS NULL
ORDER BY c.fecha_registro;


-- ============================================================
-- CONSULTA 9 - RIGHT JOIN
-- Cuántas sedes ofrecen cada tipo de espacio por día
-- ============================================================

-- Pregunta de negocio:
-- ¿En cuántas sedes se puede alquilar cada tipo de espacio por día, y a
-- qué precio promedio? Los tipos que ninguna sede ofrece por día también
-- deben aparecer.
--
-- Justificación:
-- La tabla que se quiere conservar completa es TIPO_ESPACIO y está a la
-- derecha del JOIN, por eso es RIGHT JOIN: trae todos los tipos aunque
-- no tengan tarifa por día. La cabina telefónica no se alquila por día y
-- sale con 0 sedes y precio NULL. Es lo mismo que un LEFT JOIN con las
-- tablas en el orden contrario.
--
-- Igual que en la consulta 7, la condición de modalidad va en el ON.

SELECT te.nombre AS tipo,
       COUNT(t.sede_id)    AS sedes_que_lo_ofrecen,
       ROUND(AVG(t.valor)) AS precio_dia_promedio
FROM tarifa t
INNER JOIN modalidad m ON m.modalidad_id = t.modalidad_id
                      AND m.nombre = 'Dia'
RIGHT JOIN tipo_espacio te ON te.tipo_id = t.tipo_id
GROUP BY te.tipo_id, te.nombre
ORDER BY sedes_que_lo_ofrecen DESC, te.nombre;


-- ============================================================
-- CONSULTA 10 - SELF JOIN
-- Salas que pueden reemplazar a otra en la misma sede
-- ============================================================

-- Pregunta de negocio:
-- Si una sala de reuniones se daña, ¿qué otra sala de la misma sede
-- puede recibir la reserva sin quedarse corta de capacidad?
--
-- Justificación:
-- Se compara un espacio con otros espacios: las dos partes de la
-- comparación están en la misma tabla, así que ESPACIO se une consigo
-- misma con dos alias (original y reemplazo). Las condiciones del ON
-- piden misma sede, mismo tipo, otro espacio y capacidad mayor o igual.
-- Sin el self join habría que consultar sala por sala.

SELECT s.nombre AS sede,
       original.codigo    AS sala,
       original.capacidad AS capacidad,
       reemplazo.codigo   AS puede_reemplazarla,
       reemplazo.capacidad AS capacidad_reemplazo
FROM espacio original
INNER JOIN espacio reemplazo ON reemplazo.sede_id    = original.sede_id
                            AND reemplazo.tipo_id    = original.tipo_id
                            AND reemplazo.espacio_id <> original.espacio_id
                            AND reemplazo.capacidad  >= original.capacidad
INNER JOIN tipo_espacio te   ON te.tipo_id = original.tipo_id
INNER JOIN sede s            ON s.sede_id  = original.sede_id
WHERE te.nombre = 'Sala de reuniones'
ORDER BY s.nombre, original.codigo, reemplazo.capacidad;


-- ============================================================
-- CONSULTA 11 - SELF JOIN
-- Clientes que hicieron dos reservas distintas para el mismo día
-- ============================================================

-- Pregunta de negocio:
-- Desde 2025, ¿qué clientes partieron su día en dos reservas separadas
-- en vez de una sola? Puede ser un error al reservar o una oportunidad de
-- venderles un paquete de día completo.
--
-- Justificación:
-- Hay que comparar una reserva con otra reserva del mismo cliente, así
-- que RESERVA se une consigo misma (r1 y r2). Para saber el día de cada
-- una se une también con su RESERVA_ESPACIO. La condición
-- r1.reserva_id < r2.reserva_id evita que una reserva se compare con
-- ella misma y que cada pareja salga dos veces (A-B y B-A).

SELECT DISTINCT r1.cliente_id, c.email,
       DATE(re1.inicio) AS dia,
       r1.reserva_id AS reserva_1,
       r2.reserva_id AS reserva_2
FROM reserva r1
INNER JOIN reserva r2           ON r2.cliente_id = r1.cliente_id
                               AND r2.reserva_id > r1.reserva_id
INNER JOIN reserva_espacio re1  ON re1.reserva_id = r1.reserva_id
INNER JOIN reserva_espacio re2  ON re2.reserva_id = r2.reserva_id
                               AND DATE(re2.inicio) = DATE(re1.inicio)
INNER JOIN cliente c            ON c.cliente_id = r1.cliente_id
WHERE r1.estado <> 'CANCELADA'
  AND r2.estado <> 'CANCELADA'
  AND re1.inicio >= '2025-01-01'
ORDER BY dia, r1.cliente_id;


-- ============================================================
-- CONSULTA 12 - SELF JOIN
-- Diferencia de precio de la sala de reuniones entre sedes de una ciudad
-- ============================================================

-- Pregunta de negocio:
-- Dentro de una misma ciudad, ¿qué tanto cambia el precio por hora de la
-- sala de reuniones de una sede a otra? Una diferencia grande puede
-- hacer que los clientes se pasen a la sede más barata.
--
-- Justificación:
-- Se compara una tarifa con otra tarifa: TARIFA se une consigo misma
-- (cara y barata), y cada lado con su SEDE para exigir la misma ciudad.
-- La condición cara.valor > barata.valor deja cada pareja una sola vez,
-- con la sede cara a la izquierda.

SELECT sc.ciudad,
       sc.nombre AS sede_cara,   cara.valor   AS precio_cara,
       sb.nombre AS sede_barata, barata.valor AS precio_barata,
       cara.valor - barata.valor AS diferencia
FROM tarifa cara
INNER JOIN tarifa barata  ON barata.tipo_id      = cara.tipo_id
                         AND barata.modalidad_id = cara.modalidad_id
                         AND barata.valor        < cara.valor
INNER JOIN sede sc        ON sc.sede_id = cara.sede_id
INNER JOIN sede sb        ON sb.sede_id = barata.sede_id
                         AND sb.ciudad  = sc.ciudad
INNER JOIN tipo_espacio te ON te.tipo_id      = cara.tipo_id
INNER JOIN modalidad m     ON m.modalidad_id  = cara.modalidad_id
WHERE te.nombre = 'Sala de reuniones'
  AND m.nombre  = 'Hora'
ORDER BY diferencia DESC
LIMIT 10;
