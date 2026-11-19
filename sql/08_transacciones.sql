-- ============================================================
-- TRANSACCIONES: DEMOSTRACIÓN DE COMMIT Y ROLLBACK
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: 01_ddl.sql, 02_datos_prueba.sql,
-- 07_procedimientos_funciones.sql y después este archivo. Funciona
-- igual si antes se corrieron 03, 04, 05 y 06.
--
-- Muestra el número de filas de cada tabla antes y después de cada
-- caso. En los casos con COMMIT las filas aumentan; en los casos
-- con ROLLBACK quedan exactamente iguales.
--
--   Parte A  Transacción escrita a mano: START TRANSACTION, tres
--            INSERT en tres tablas, condición de error y ROLLBACK.
--   Parte B  T1 sp_registrar_cliente: 1 COMMIT y 3 ROLLBACK.
--   Parte C  T2 sp_crear_reserva:     2 COMMIT y 4 ROLLBACK.
--   Parte D  Las tres funciones dentro de un SELECT.
--   Parte E  T3 sp_registrar_pago y sp_cancelar_reserva.
--
-- El script corre de principio a fin sin detenerse. Los casos de
-- error se ejecutan con sp_demo_intentar, que atrapa el error y lo
-- muestra como resultado en vez de cortar el script. Para ver el
-- error como lo vería la aplicación, se puede copiar la llamada
-- que aparece en la columna "llamada" y ejecutarla sola.
--
-- Usa fechas de marzo de 2027, que no tienen reservas en los
-- datos de prueba, y los espacios de la Sede Chapinero (sede 1),
-- que 03_consultas.sql no modifica:
--   espacio 6   SR-01  sala de reuniones   68.500 / hora
--   espacio 1   EF-01  escritorio flexible 12.000 / hora
--   espacio 2   EF-02  escritorio flexible 12.000 / hora
--   espacio 4   ED-02  escritorio dedicado 74.500 / día
--   espacio 10  CB-01  cabina telefónica    sin tarifa por día
--   espacio 24  EF-01  Sede Usaquén (otra sede)
--
-- Se puede correr varias veces: al empezar borra lo que dejó una
-- ejecución anterior (reservas de marzo de 2027 y los clientes de
-- la demostración).
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;


-- ------------------------------------------------------------
-- 0. Preparación
-- ------------------------------------------------------------

-- Borrar lo que dejó una ejecución anterior del script
DELETE FROM reserva
WHERE reserva_id IN (
    SELECT reserva_id FROM (
        SELECT DISTINCT re.reserva_id
        FROM reserva_espacio re
        WHERE re.inicio >= '2027-03-01' AND re.inicio < '2027-04-01'
    ) AS previas
);

DELETE FROM reserva
WHERE cliente_id IN (SELECT cliente_id FROM cliente
                     WHERE email IN ('compras@nubeverde.com.co', 'laura.quintero@gmail.com'));

DELETE FROM cliente
WHERE email IN ('compras@nubeverde.com.co', 'laura.quintero@gmail.com');

DROP PROCEDURE IF EXISTS sp_demo_conteo;
DROP PROCEDURE IF EXISTS sp_demo_intentar;

DELIMITER $$

-- Muestra cuántas filas tiene cada tabla que tocan las transacciones
CREATE PROCEDURE sp_demo_conteo(IN p_paso VARCHAR(80))
BEGIN
    SELECT p_paso AS paso,
           (SELECT COUNT(*) FROM cliente)          AS cliente,
           (SELECT COUNT(*) FROM persona_natural)  AS persona,
           (SELECT COUNT(*) FROM empresa)          AS empresa,
           (SELECT COUNT(*) FROM telefono_cliente) AS telefono,
           (SELECT COUNT(*) FROM reserva)          AS reserva,
           (SELECT COUNT(*) FROM reserva_espacio)  AS reserva_espacio,
           (SELECT COUNT(*) FROM cuota)            AS cuota,
           (SELECT COUNT(*) FROM cuota WHERE fecha_pago IS NOT NULL) AS cuotas_pagadas;
END$$

-- Ejecuta una llamada y, si falla, muestra el mensaje en vez de
-- detener el script. El CONTINUE HANDLER atrapa el error y
-- GET DIAGNOSTICS lee el texto que puso el SIGNAL.
CREATE PROCEDURE sp_demo_intentar(IN p_caso VARCHAR(80), IN p_llamada TEXT)
BEGIN
    DECLARE v_error TEXT DEFAULT NULL;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        GET DIAGNOSTICS CONDITION 1 v_error = MESSAGE_TEXT;

    SET @demo_llamada = p_llamada;
    PREPARE st FROM @demo_llamada;
    EXECUTE st;
    DEALLOCATE PREPARE st;

    SELECT p_caso AS caso,
           IF(v_error IS NULL, 'COMMIT', 'ROLLBACK') AS resultado,
           COALESCE(v_error, '') AS mensaje,
           p_llamada AS llamada;
END$$

DELIMITER ;


-- ============================================================
-- PARTE A. Transacción escrita a mano con ROLLBACK
-- ============================================================
--
-- Una reserva necesita filas en tres tablas: reserva,
-- reserva_espacio y cuota. Aquí se insertan las tres dentro de una
-- transacción y al final se revisa una condición de negocio: el
-- espacio ya estaba ocupado. Como la condición falla, se ejecuta
-- ROLLBACK y las tres filas desaparecen.

-- Ocupa la sala SR-01 el 1 de marzo de 9 a 12 (esta sí se confirma)
CALL sp_crear_reserva(2, 1, '[6, 1, 2]', '2027-03-01', '09:00', '12:00',
                      2, 'Transferencia', @reserva_ocupa);

CALL sp_demo_conteo('A0. Antes de la transacción manual');

START TRANSACTION;

    INSERT INTO reserva (cliente_id, modalidad_id) VALUES (1, 1);
    SET @reserva_manual = LAST_INSERT_ID();

    INSERT INTO reserva_espacio (reserva_id, espacio_id, inicio, fin, tarifa_aplicada)
    VALUES (@reserva_manual, 6, '2027-03-01 11:00', '2027-03-01 13:00', 68500);

    INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
    VALUES (@reserva_manual, 1, 137000, NULL, NULL);

    -- Dentro de la transacción las tres filas sí existen
    CALL sp_demo_conteo('A1. Dentro de la transacción, sin confirmar');

    -- Condición de error: ¿la sala ya tenía otra reserva a esa hora?
    SELECT IF(fn_espacio_disponible(6, '2027-03-01 11:00', '2027-03-01 13:00') = 0
              OR EXISTS (SELECT 1 FROM reserva_espacio re
                          JOIN reserva r ON r.reserva_id = re.reserva_id
                         WHERE re.espacio_id = 6
                           AND re.reserva_id <> @reserva_manual
                           AND r.estado <> 'CANCELADA'
                           AND re.inicio < '2027-03-01 13:00'
                           AND re.fin    > '2027-03-01 11:00'),
              'La sala SR-01 ya está ocupada de 9 a 12: se hace ROLLBACK',
              'La sala está libre: se haría COMMIT') AS verificacion;

ROLLBACK;

-- Después del ROLLBACK ninguna de las tres filas quedó
CALL sp_demo_conteo('A2. Después del ROLLBACK');

-- Lo único que el ROLLBACK no devuelve es el número de
-- AUTO_INCREMENT: @reserva_manual ya se gastó, y la siguiente reserva
-- recibe el número siguiente. Quedan huecos en reserva_id, y no es
-- un error: un id solo tiene que ser único, no consecutivo. Por eso
-- num_cuota, que sí debe ser consecutivo dentro de cada reserva, no
-- usa AUTO_INCREMENT.
SELECT @reserva_manual AS id_gastado_por_el_rollback,
       (SELECT MAX(reserva_id) FROM reserva) AS ultima_reserva_guardada;


-- ============================================================
-- PARTE B. T1 sp_registrar_cliente
-- ============================================================

CALL sp_demo_conteo('B0. Antes');

-- B1. COMMIT: empresa nueva con dos teléfonos.
--     cliente +1, empresa +1, telefono +2.
CALL sp_demo_intentar('B1. Empresa nueva',
    'CALL sp_registrar_cliente(''EMPRESA'', ''compras@nubeverde.com.co'',
        NULL, NULL, NULL, NULL,
        ''901445566-7'', ''Nube Verde Tecnología S.A.S.'', ''Mónica Lozano'',
        ''["3015558899", "6017778899"]'', @cliente_b1)');

CALL sp_demo_conteo('B1. Después del COMMIT');

-- B2. ROLLBACK: el documento 70719489 ya es de Andrés Patiño
--     (cliente 1). cliente alcanza a insertarse y se deshace, así
--     que no queda un cliente sin subclase.
CALL sp_demo_intentar('B2. Documento repetido',
    'CALL sp_registrar_cliente(''NATURAL'', ''ana.perez@gmail.com'',
        ''70719489'', ''Ana'', ''Pérez Gil'', ''1999-05-10'',
        NULL, NULL, NULL, ''["3001112233"]'', @cliente_b2)');

-- B3. ROLLBACK: cliente y empresa alcanzan a insertarse; al revisar
--     los teléfonos aparece "31-ABC" y se deshacen los dos.
CALL sp_demo_intentar('B3. Teléfono inválido',
    'CALL sp_registrar_cliente(''EMPRESA'', ''info@ferreteriaelsol.com.co'',
        NULL, NULL, NULL, NULL,
        ''900998877-3'', ''Ferretería El Sol Ltda.'', ''Ricardo Peña'',
        ''["3109998877", "31-ABC"]'', @cliente_b3)');

-- B4. Error de entrada: menor de edad. Se detecta antes de empezar
--     la transacción, así que no hay nada que deshacer.
CALL sp_demo_intentar('B4. Menor de edad',
    'CALL sp_registrar_cliente(''NATURAL'', ''tomas.ruiz@gmail.com'',
        ''1012345678'', ''Tomás'', ''Ruiz Mora'', ''2012-05-10'',
        NULL, NULL, NULL, ''["3001112233"]'', @cliente_b4)');

CALL sp_demo_conteo('B5. Después de los errores (igual que B1)');


-- ============================================================
-- PARTE C. T2 sp_crear_reserva
-- ============================================================

CALL sp_demo_conteo('C0. Antes');

-- C1. COMMIT: Nube Verde (registrada en B1) reserva por día el
--     escritorio dedicado ED-02, en 3 cuotas, sin pagar todavía.
--     reserva +1, reserva_espacio +1, cuota +3 (ninguna pagada).
SET @cliente_nube = (SELECT cliente_id FROM cliente WHERE email = 'compras@nubeverde.com.co');
SET @llamada = CONCAT('CALL sp_crear_reserva(', @cliente_nube,
                      ', 2, ''[4]'', ''2027-03-02'', NULL, NULL, 3, NULL, @reserva_c1)');
CALL sp_demo_intentar('C1. Reserva por día, 3 cuotas, PENDIENTE', @llamada);

CALL sp_demo_conteo('C1. Después del COMMIT');

-- C2. ROLLBACK por cruce: la sala SR-01 ya está ocupada de 9 a 12
--     (parte A). Se alcanzan a insertar reserva y reserva_espacio.
CALL sp_demo_intentar('C2. Cruce de horario',
    'CALL sp_crear_reserva(1, 1, ''[6]'', ''2027-03-01'',
        ''11:00'', ''13:00'', 1, NULL, @reserva_c2)');

-- C3. ROLLBACK por espacio sin tarifa: el escritorio ED-01 sí tiene
--     tarifa por día y se alcanza a insertar; la cabina CB-01 no
--     tiene. Se deshacen reserva y el escritorio.
CALL sp_demo_intentar('C3. Cabina telefónica por día',
    'CALL sp_crear_reserva(1, 2, ''[3, 10]'', ''2027-03-03'',
        NULL, NULL, 1, NULL, @reserva_c3)');

-- C4. Error de entrada: espacios de dos sedes distintas.
CALL sp_demo_intentar('C4. Espacios de varias sedes',
    'CALL sp_crear_reserva(1, 1, ''[3, 24]'', ''2027-03-03'',
        ''09:00'', ''10:00'', 1, NULL, @reserva_c4)');

-- C5. Error de entrada: el cliente no existe (SIGNAL en vez de un
--     error de llave foránea).
CALL sp_demo_intentar('C5. Cliente inexistente',
    'CALL sp_crear_reserva(99999, 1, ''[3]'', ''2027-03-03'',
        ''09:00'', ''10:00'', 1, NULL, @reserva_c5)');

-- C6. Error de entrada: fuera del horario de la sede (7:00 a 21:00).
CALL sp_demo_intentar('C6. Antes de que abra la sede',
    'CALL sp_crear_reserva(1, 1, ''[3]'', ''2027-03-03'',
        ''06:00'', ''08:00'', 1, NULL, @reserva_c6)');

CALL sp_demo_conteo('C7. Después de los errores (igual que C1)');


-- ============================================================
-- PARTE D. Las funciones dentro de un SELECT
-- ============================================================

-- D1. Valor y saldo de las reservas creadas en esta demostración
SELECT r.reserva_id, r.estado, c.email,
       fn_valor_reserva(r.reserva_id)   AS valor,
       fn_saldo_pendiente(r.reserva_id) AS saldo
FROM reserva r
JOIN cliente c ON c.cliente_id = r.cliente_id
WHERE r.reserva_id IN (@reserva_ocupa, @reserva_c1)
ORDER BY r.reserva_id;

-- D2. ¿Qué espacios de la Sede Chapinero están libres el 1 de marzo
--     de 2027 de 10 a 11? SR-01, EF-01 y EF-02 salen ocupados.
SELECT e.codigo, te.nombre AS tipo, e.capacidad,
       fn_espacio_disponible(e.espacio_id, '2027-03-01 10:00', '2027-03-01 11:00') AS libre
FROM espacio e
JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
WHERE e.sede_id = 1
ORDER BY libre, e.codigo;

-- D3. Las cinco reservas vigentes con más saldo por cobrar
SELECT r.reserva_id, r.estado, r.cliente_id,
       fn_valor_reserva(r.reserva_id)   AS valor,
       fn_saldo_pendiente(r.reserva_id) AS saldo
FROM reserva r
WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA')
ORDER BY saldo DESC
LIMIT 5;


-- ============================================================
-- PARTE E. T3 sp_registrar_pago y sp_cancelar_reserva
-- ============================================================

-- E1. Pago de la cuota 1 de la reserva C1: pasa de PENDIENTE a
--     CONFIRMADA (cuota + reserva en la misma transacción).
SET @llamada = CONCAT('CALL sp_registrar_pago(', @reserva_c1, ', ''Nequi'', @cuota_e1, @monto_e1)');
CALL sp_demo_intentar('E1. Pago de la cuota 1', @llamada);

SELECT reserva_id, estado, fn_saldo_pendiente(reserva_id) AS saldo,
       @cuota_e1 AS cuota_pagada, @monto_e1 AS monto
FROM reserva WHERE reserva_id = @reserva_c1;

-- E2. Pago de la cuota 2 de la reserva de la parte A: queda en 0.
SET @llamada = CONCAT('CALL sp_registrar_pago(', @reserva_ocupa, ', ''PSE'', @cuota_e2, @monto_e2)');
CALL sp_demo_intentar('E2. Pago de la última cuota', @llamada);

-- E3. Error: ya no quedan cuotas por pagar.
CALL sp_demo_intentar('E3. Reserva ya pagada', @llamada);

-- E4. Error: la reserva 7 está cancelada.
CALL sp_demo_intentar('E4. Reserva cancelada',
    'CALL sp_registrar_pago(7, ''Efectivo'', @cuota_e4, @monto_e4)');

-- E5. Error: la reserva no existe.
CALL sp_demo_intentar('E5. Reserva inexistente',
    'CALL sp_registrar_pago(99999, ''Efectivo'', @cuota_e5, @monto_e5)');

-- E6. Error: no se puede cancelar una reserva con pagos.
SET @llamada = CONCAT('CALL sp_cancelar_reserva(', @reserva_ocupa, ')');
CALL sp_demo_intentar('E6. Cancelar una reserva con pagos', @llamada);

-- E7. Cancelar una reserva sin pagos libera el espacio.
CALL sp_crear_reserva(1, 1, '[7]', '2027-03-04', '14:00', '16:00', 1, NULL, @reserva_e7);

SELECT fn_espacio_disponible(7, '2027-03-04 14:00', '2027-03-04 16:00') AS sr02_libre_antes;

CALL sp_cancelar_reserva(@reserva_e7);

SELECT r.estado, fn_saldo_pendiente(r.reserva_id) AS saldo,
       fn_espacio_disponible(7, '2027-03-04 14:00', '2027-03-04 16:00') AS sr02_libre_despues
FROM reserva r WHERE r.reserva_id = @reserva_e7;

CALL sp_demo_conteo('Final');


-- ------------------------------------------------------------
-- Limpieza: los procedimientos de apoyo no son parte del sistema
-- ------------------------------------------------------------
DROP PROCEDURE sp_demo_conteo;
DROP PROCEDURE sp_demo_intentar;
