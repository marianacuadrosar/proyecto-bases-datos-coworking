-- ============================================================
-- FUNCIONES, PROCEDIMIENTOS Y TRANSACCIONES
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: 01_ddl.sql, 02_datos_prueba.sql y después este
-- archivo. Funciona igual si antes se corrieron 03, 04, 05 y 06.
-- La demostración de COMMIT y ROLLBACK está en 08_transacciones.sql.
--
-- Contenido:
--
--   Funciones (se usan dentro de un SELECT):
--     fn_valor_reserva(reserva)                 atributo derivado valor_total
--     fn_saldo_pendiente(reserva)               valor menos lo pagado
--     fn_espacio_disponible(espacio, ini, fin)  1 si está libre, 0 si no
--
--   Procedimientos con transacción:
--     T1 sp_registrar_cliente   cliente + subclase + teléfonos
--     T2 sp_crear_reserva       reserva + reserva_espacio + cuota
--     T3 sp_registrar_pago      cuota + reserva       (IF / ELSEIF)
--        sp_cancelar_reserva    reserva               (IF / ELSEIF)
--
-- Los procedimientos son los que llama la aplicación. Ninguno deja
-- que MySQL falle con un error técnico: cada entrada inválida se
-- detecta antes y se responde con SIGNAL SQLSTATE '45000' y un
-- mensaje que se le puede mostrar tal cual al usuario.
--
-- Reglas que respetan, las mismas de 02_verificacion_datos.sql:
--   - Cada cliente queda en una sola subclase, la de tipo_cliente.
--   - Ningún email, documento ni NIT se repite.
--   - Una persona natural tiene al menos 18 años al registrarse.
--   - Un espacio no tiene dos reservas vigentes que se crucen.
--   - Todos los espacios de una reserva son de la misma sede.
--   - La reserva cae dentro del horario de la sede. Por día va de la
--     apertura al cierre.
--   - tarifa_aplicada se copia de la tabla tarifa al reservar.
--   - Las cuotas suman exactamente el valor de la reserva.
--   - Una reserva CONFIRMADA tiene pagada la cuota 1; una PENDIENTE
--     o CANCELADA no tiene cuotas pagadas.
--
-- ------------------------------------------------------------
-- Cómo funciona el manejo de errores
-- ------------------------------------------------------------
-- Las cuatro transacciones siguen el mismo esquema:
--
--   DECLARE EXIT HANDLER FOR SQLEXCEPTION
--   BEGIN
--       ROLLBACK;     -- deshace todo lo que se alcanzó a hacer
--       RESIGNAL;     -- devuelve el mismo error a quien llamó
--   END;
--   ...validaciones que no modifican nada...
--   START TRANSACTION;
--       INSERT ...;
--       IF <regla rota> THEN
--           SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...';
--       END IF;
--       INSERT ...;
--   COMMIT;
--
--   SIGNAL lanza un error a propósito con el mensaje que uno
--   escribe. SQLSTATE '45000' es el código estándar de "error
--   definido por el usuario" (MySQL lo muestra como error 1644).
--
--   El EXIT HANDLER se ejecuta solo cuando ocurre cualquier error
--   dentro del procedimiento: uno nuestro (SIGNAL) o uno de MySQL
--   (un CHECK violado, una llave duplicada). Hace ROLLBACK y
--   RESIGNAL. Sin RESIGNAL el error se perdería y la aplicación
--   creería que todo salió bien. EXIT significa que, después del
--   handler, el procedimiento termina.
--
--   Las validaciones que solo revisan la entrada van antes de
--   START TRANSACTION, porque todavía no hay nada que deshacer. Las
--   que dependen de lo ya insertado o de lo que otra sesión puede
--   estar cambiando (tarifa, cruce de horario, documento repetido)
--   van adentro, y ahí el ROLLBACK sí deshace filas.
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;

DROP FUNCTION  IF EXISTS fn_valor_reserva;
DROP FUNCTION  IF EXISTS fn_saldo_pendiente;
DROP FUNCTION  IF EXISTS fn_espacio_disponible;
DROP PROCEDURE IF EXISTS sp_registrar_cliente;
DROP PROCEDURE IF EXISTS sp_crear_reserva;
DROP PROCEDURE IF EXISTS sp_registrar_pago;
DROP PROCEDURE IF EXISTS sp_cancelar_reserva;

DELIMITER $$


-- ============================================================
-- FUNCIÓN 1: fn_valor_reserva
-- ============================================================
--
-- Calcula el atributo derivado valor_total de una reserva, que no
-- se guarda como columna. Es la misma fórmula de
-- 06_consultas_analisis.sql:
--   cada fila de reserva_espacio vale tarifa_aplicada x horas
--   (modalidad Hora) o tarifa_aplicada x 1 (modalidad Dia).
-- Devuelve NULL si la reserva no existe.
--
-- Ejemplo:
--   SELECT reserva_id, estado, fn_valor_reserva(reserva_id) AS valor
--   FROM reserva WHERE estado = 'CONFIRMADA';

CREATE FUNCTION fn_valor_reserva(p_reserva_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_valor DECIMAL(12,2);

    SELECT ROUND(SUM(re.tarifa_aplicada *
                     CASE WHEN m.nombre = 'Hora'
                          THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                          ELSE 1 END), 2)
      INTO v_valor
      FROM reserva r
      JOIN modalidad m        ON m.modalidad_id = r.modalidad_id
      JOIN reserva_espacio re ON re.reserva_id  = r.reserva_id
     WHERE r.reserva_id = p_reserva_id;

    RETURN v_valor;
END$$


-- ============================================================
-- FUNCIÓN 2: fn_saldo_pendiente
-- ============================================================
--
-- Lo que falta por pagar: valor de la reserva menos las cuotas con
-- fecha_pago. Sirve igual si la reserva tiene plan de cuotas o si
-- todavía no tiene ninguna. Una reserva cancelada no se cobra, así
-- que su saldo es 0.
--
-- Ejemplo:
--   SELECT reserva_id, fn_valor_reserva(reserva_id) AS valor,
--          fn_saldo_pendiente(reserva_id) AS saldo
--   FROM reserva WHERE estado IN ('PENDIENTE', 'CONFIRMADA');

CREATE FUNCTION fn_saldo_pendiente(p_reserva_id INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_pagado DECIMAL(12,2);

    SELECT estado INTO v_estado FROM reserva WHERE reserva_id = p_reserva_id;

    IF v_estado IS NULL THEN
        RETURN NULL;
    ELSEIF v_estado = 'CANCELADA' THEN
        RETURN 0;
    END IF;

    SELECT COALESCE(SUM(monto), 0) INTO v_pagado
      FROM cuota
     WHERE reserva_id = p_reserva_id
       AND fecha_pago IS NOT NULL;

    RETURN COALESCE(fn_valor_reserva(p_reserva_id), 0) - v_pagado;
END$$


-- ============================================================
-- FUNCIÓN 3: fn_espacio_disponible
-- ============================================================
--
-- Devuelve 1 si el espacio no tiene ninguna reserva vigente que se
-- cruce con el intervalo [p_inicio, p_fin), y 0 si la tiene. Las
-- reservas canceladas no ocupan el espacio.
--
-- Dos intervalos se cruzan si uno empieza antes de que el otro
-- termine:   otro.inicio < p_fin  AND  otro.fin > p_inicio
--   09:00-12:00 y 11:00-13:00  se cruzan
--   09:00-12:00 y 12:00-14:00  no: una termina cuando la otra empieza
--
-- Ejemplo: salas de reuniones de la Sede Chapinero libres el 15 de
-- diciembre de 2026 de 9 a 11:
--   SELECT e.codigo, e.capacidad
--   FROM espacio e JOIN tipo_espacio te ON te.tipo_id = e.tipo_id
--   WHERE e.sede_id = 1 AND te.nombre = 'Sala de reuniones'
--     AND fn_espacio_disponible(e.espacio_id,
--             '2026-12-15 09:00', '2026-12-15 11:00') = 1;

CREATE FUNCTION fn_espacio_disponible(p_espacio_id INT, p_inicio DATETIME, p_fin DATETIME)
RETURNS TINYINT
READS SQL DATA
BEGIN
    IF EXISTS (SELECT 1
                 FROM reserva_espacio re
                 JOIN reserva r ON r.reserva_id = re.reserva_id
                WHERE re.espacio_id = p_espacio_id
                  AND r.estado <> 'CANCELADA'
                  AND re.inicio < p_fin
                  AND re.fin    > p_inicio) THEN
        RETURN 0;
    END IF;
    RETURN 1;
END$$


-- ============================================================
-- T1: sp_registrar_cliente
-- ============================================================
--
-- Registra un cliente con su subclase y sus teléfonos en una sola
-- transacción.
--
-- Tablas que modifica: cliente, persona_natural o empresa, y
-- telefono_cliente.
--
-- Por qué necesita transacción: la especialización es disjunta y
-- total. La llave foránea no lo garantiza: si se inserta el
-- cliente y luego falla la empresa, queda un cliente que no es ni
-- persona ni empresa. Con la transacción quedan las tres tablas o
-- ninguna. El IF / ELSEIF sobre p_tipo_cliente decide la subclase,
-- así que tipo_cliente siempre coincide con la tabla.
--
-- Parámetros: para NATURAL se usan documento, nombres, apellidos y
-- fecha de nacimiento; para EMPRESA, NIT, razón social y contacto.
-- Los que no aplican se envían en NULL. Los teléfonos llegan como
-- arreglo JSON, porque MySQL no recibe listas: '["3104567890"]'.
--
-- Ejemplo:
--   CALL sp_registrar_cliente('EMPRESA', 'compras@nubeverde.com.co',
--        NULL, NULL, NULL, NULL,
--        '901445566-7', 'Nube Verde S.A.S.', 'Mónica Lozano',
--        '["3015558899", "6017778899"]', @cliente);

CREATE PROCEDURE sp_registrar_cliente(
    IN  p_tipo_cliente      VARCHAR(20),
    IN  p_email             VARCHAR(100),
    IN  p_documento         VARCHAR(20),
    IN  p_nombres           VARCHAR(60),
    IN  p_apellidos         VARCHAR(60),
    IN  p_fecha_nacimiento  DATE,
    IN  p_nit               VARCHAR(15),
    IN  p_razon_social      VARCHAR(120),
    IN  p_nombre_contacto   VARCHAR(100),
    IN  p_telefonos         JSON,
    OUT p_cliente_id        INT
)
BEGIN
    DECLARE v_msg       VARCHAR(128);
    DECLARE v_telefono  VARCHAR(40);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_cliente_id = NULL;
        RESIGNAL;
    END;

    SET p_cliente_id = NULL;

    -- ---- Validaciones de entrada (todavía no se modifica nada) ----

    IF p_tipo_cliente IS NULL OR p_tipo_cliente NOT IN ('NATURAL', 'EMPRESA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El tipo de cliente debe ser NATURAL o EMPRESA';
    END IF;

    IF p_email IS NULL OR NOT REGEXP_LIKE(p_email, '^[^@ ]+@[^@ ]+\\.[^@ ]+$') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El email no tiene un formato válido';
    END IF;

    IF p_telefonos IS NULL OR JSON_TYPE(p_telefonos) <> 'ARRAY'
       OR JSON_LENGTH(p_telefonos) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente debe tener al menos un teléfono';
    END IF;

    IF p_tipo_cliente = 'NATURAL' THEN
        IF p_documento IS NULL OR p_nombres IS NULL OR p_apellidos IS NULL
           OR p_fecha_nacimiento IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Faltan datos: documento, nombres, apellidos y fecha de nacimiento son obligatorios';
        END IF;
        IF TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE()) < 18 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'La persona debe ser mayor de edad para registrarse';
        END IF;
    ELSEIF p_tipo_cliente = 'EMPRESA' THEN
        IF p_nit IS NULL OR p_razon_social IS NULL OR p_nombre_contacto IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Faltan datos: NIT, razón social y nombre de contacto son obligatorios';
        END IF;
        IF NOT REGEXP_LIKE(p_nit, '^[0-9]{9}-[0-9]$') THEN
            SET v_msg = LEFT(CONCAT('El NIT ', p_nit, ' no tiene el formato 123456789-0'), 128);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;

    -- ---- Transacción ----

    START TRANSACTION;

    IF EXISTS (SELECT 1 FROM cliente WHERE email = p_email) THEN
        SET v_msg = LEFT(CONCAT('Ya existe un cliente con el email ', p_email), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- 1. Superclase
    INSERT INTO cliente (email, tipo_cliente)
    VALUES (p_email, p_tipo_cliente);

    SET p_cliente_id = LAST_INSERT_ID();

    -- 2. Subclase
    IF p_tipo_cliente = 'NATURAL' THEN
        IF EXISTS (SELECT 1 FROM persona_natural WHERE documento = p_documento) THEN
            -- cliente ya quedó insertado: el SIGNAL activa el ROLLBACK
            SET v_msg = LEFT(CONCAT('Ya existe una persona con el documento ', p_documento), 128);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        INSERT INTO persona_natural (cliente_id, documento, nombres, apellidos, fecha_nacimiento)
        VALUES (p_cliente_id, p_documento, p_nombres, p_apellidos, p_fecha_nacimiento);

    ELSEIF p_tipo_cliente = 'EMPRESA' THEN
        IF EXISTS (SELECT 1 FROM empresa WHERE nit = p_nit) THEN
            SET v_msg = LEFT(CONCAT('Ya existe una empresa con el NIT ', p_nit), 128);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        INSERT INTO empresa (cliente_id, nit, razon_social, nombre_contacto)
        VALUES (p_cliente_id, p_nit, p_razon_social, p_nombre_contacto);
    END IF;

    -- 3. Teléfonos (atributo multivaluado): 7 dígitos fijo o 10 celular
    SELECT MIN(jt.telefono) INTO v_telefono
      FROM JSON_TABLE(p_telefonos, '$[*]' COLUMNS (telefono VARCHAR(40) PATH '$')) AS jt
     WHERE jt.telefono IS NULL
        OR NOT REGEXP_LIKE(jt.telefono, '^([0-9]{7}|[0-9]{10})$');

    IF v_telefono IS NOT NULL THEN
        -- cliente y su subclase ya quedaron insertados: se deshacen
        SET v_msg = LEFT(CONCAT('El teléfono ', v_telefono, ' no es válido: debe tener 7 o 10 dígitos'), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    INSERT INTO telefono_cliente (cliente_id, telefono)
    SELECT DISTINCT p_cliente_id, jt.telefono
      FROM JSON_TABLE(p_telefonos, '$[*]' COLUMNS (telefono VARCHAR(40) PATH '$')) AS jt;

    COMMIT;
END$$


-- ============================================================
-- T2: sp_crear_reserva
-- ============================================================
--
-- Crea una reserva de uno o varios espacios de una misma sede, con
-- su plan de cuotas. Si se indica un método de pago, la cuota 1
-- queda pagada y la reserva queda CONFIRMADA; si no, PENDIENTE.
--
-- Tablas que modifica:
--   1. reserva          INSERT del encabezado
--   2. reserva_espacio  INSERT de cada espacio, con la tarifa vigente
--   3. cuota            INSERT del plan de cuotas
--   4. cuota y reserva  UPDATE de la cuota 1 y del estado, si se paga
--
-- Hace ROLLBACK si, con filas ya insertadas:
--   - algún espacio no tiene tarifa para esa modalidad en su sede
--     (por ejemplo, una cabina telefónica por día);
--   - algún espacio ya está reservado en un horario que se cruza.
--
-- Parámetros:
--   p_espacios     arreglo JSON de espacio_id: '[6, 1, 2]'
--   p_modalidad_id 1 = Hora, 2 = Dia
--   p_fecha        día de uso (hoy o después)
--   p_hora_inicio,
--   p_hora_fin     solo para modalidad Hora. Por día se usa el
--                  horario completo de la sede y pueden ir en NULL.
--   p_num_cuotas   de 1 a 3
--   p_metodo_pago  NULL para dejarla PENDIENTE
--
-- Ejemplo: Tequendama Ingeniería (cliente 2) reserva la sala SR-01 y
-- los escritorios EF-01 y EF-02 de la Sede Chapinero de 9 a 12, en
-- dos cuotas, y paga la primera:
--   CALL sp_crear_reserva(2, 1, '[6, 1, 2]', '2026-12-15',
--        '09:00', '12:00', 2, 'Transferencia', @reserva);

CREATE PROCEDURE sp_crear_reserva(
    IN  p_cliente_id    INT,
    IN  p_modalidad_id  INT,
    IN  p_espacios      JSON,
    IN  p_fecha         DATE,
    IN  p_hora_inicio   TIME,
    IN  p_hora_fin      TIME,
    IN  p_num_cuotas    INT,
    IN  p_metodo_pago   VARCHAR(30),
    OUT p_reserva_id    INT
)
BEGIN
    DECLARE v_msg         VARCHAR(128);
    DECLARE v_modalidad   VARCHAR(20);
    DECLARE v_pedidos     INT;
    DECLARE v_distintos   INT;
    DECLARE v_id          INT;
    DECLARE v_sedes       INT;
    DECLARE v_apertura    TIME;
    DECLARE v_cierre      TIME;
    DECLARE v_inicio      DATETIME;
    DECLARE v_fin         DATETIME;
    DECLARE v_codigo      VARCHAR(100);
    DECLARE v_tipo        VARCHAR(50);
    DECLARE v_valor       DECIMAL(12,2);
    DECLARE v_monto       DECIMAL(12,2);
    DECLARE i             INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_espacios_reserva;
        SET p_reserva_id = NULL;
        RESIGNAL;
    END;

    SET p_reserva_id = NULL;
    SET p_num_cuotas = COALESCE(p_num_cuotas, 1);

    -- ---- Validaciones de entrada (todavía no se modifica nada) ----

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cliente_id = p_cliente_id) THEN
        SET v_msg = CONCAT('El cliente ', IFNULL(p_cliente_id, 'NULL'), ' no existe');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    SELECT nombre INTO v_modalidad FROM modalidad WHERE modalidad_id = p_modalidad_id;
    IF v_modalidad IS NULL THEN
        SET v_msg = CONCAT('La modalidad ', IFNULL(p_modalidad_id, 'NULL'), ' no existe');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    IF p_fecha IS NULL OR p_fecha < CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La fecha de la reserva debe ser hoy o una fecha futura';
    END IF;

    IF p_num_cuotas NOT BETWEEN 1 AND 3 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El número de cuotas debe estar entre 1 y 3';
    END IF;

    IF p_metodo_pago IS NOT NULL AND p_metodo_pago NOT IN
       ('Efectivo', 'Tarjeta de crédito', 'Tarjeta débito', 'Transferencia', 'PSE', 'Nequi') THEN
        SET v_msg = LEFT(CONCAT('El método de pago ', p_metodo_pago, ' no es válido'), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    IF p_espacios IS NULL OR JSON_TYPE(p_espacios) <> 'ARRAY'
       OR JSON_LENGTH(p_espacios) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva debe incluir al menos un espacio';
    END IF;

    -- El JSON se pasa a una tabla temporal para validarlo con SQL
    DROP TEMPORARY TABLE IF EXISTS tmp_espacios_reserva;
    CREATE TEMPORARY TABLE tmp_espacios_reserva AS
        SELECT jt.espacio_id
          FROM JSON_TABLE(p_espacios, '$[*]' COLUMNS (espacio_id INT PATH '$')) AS jt;

    SELECT COUNT(*), COUNT(DISTINCT espacio_id) INTO v_pedidos, v_distintos
      FROM tmp_espacios_reserva;

    IF v_distintos < v_pedidos THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Un mismo espacio no puede aparecer dos veces en la reserva';
    END IF;

    SELECT MIN(t.espacio_id) INTO v_id
      FROM tmp_espacios_reserva t
      LEFT JOIN espacio e ON e.espacio_id = t.espacio_id
     WHERE e.espacio_id IS NULL;

    IF v_id IS NOT NULL OR EXISTS (SELECT 1 FROM tmp_espacios_reserva WHERE espacio_id IS NULL) THEN
        SET v_msg = CONCAT('El espacio ', IFNULL(v_id, 'NULL'), ' no existe');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    SELECT COUNT(DISTINCT e.sede_id), MIN(s.hora_apertura), MIN(s.hora_cierre)
      INTO v_sedes, v_apertura, v_cierre
      FROM tmp_espacios_reserva t
      JOIN espacio e ON e.espacio_id = t.espacio_id
      JOIN sede s    ON s.sede_id    = e.sede_id;

    IF v_sedes > 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Todos los espacios de una reserva deben ser de la misma sede';
    END IF;

    -- Horario: por día, de la apertura al cierre; por hora, el pedido
    IF v_modalidad = 'Dia' THEN
        SET v_inicio = TIMESTAMP(p_fecha, v_apertura);
        SET v_fin    = TIMESTAMP(p_fecha, v_cierre);
    ELSEIF p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Una reserva por hora necesita hora de inicio y hora de fin';
    ELSEIF p_hora_fin <= p_hora_inicio THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La hora de fin debe ser posterior a la hora de inicio';
    ELSEIF p_hora_inicio < v_apertura OR p_hora_fin > v_cierre THEN
        SET v_msg = CONCAT('La sede atiende de ', TIME_FORMAT(v_apertura, '%H:%i'),
                           ' a ', TIME_FORMAT(v_cierre, '%H:%i'));
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSE
        SET v_inicio = TIMESTAMP(p_fecha, p_hora_inicio);
        SET v_fin    = TIMESTAMP(p_fecha, p_hora_fin);
    END IF;

    -- ---- Transacción ----

    START TRANSACTION;

    -- Bloquea los espacios pedidos hasta el COMMIT o el ROLLBACK. Si
    -- otra sesión intenta reservar los mismos espacios al mismo tiempo,
    -- espera, y cuando sigue ya ve esta reserva y detecta el cruce.
    SELECT COUNT(*) INTO v_id
      FROM espacio
     WHERE espacio_id IN (SELECT espacio_id FROM tmp_espacios_reserva)
       FOR UPDATE;

    -- 1. Encabezado (estado PENDIENTE por el DEFAULT de la tabla)
    INSERT INTO reserva (cliente_id, modalidad_id)
    VALUES (p_cliente_id, p_modalidad_id);

    SET p_reserva_id = LAST_INSERT_ID();

    -- 2. Espacios con la tarifa vigente copiada en tarifa_aplicada.
    --    El JOIN con tarifa deja por fuera los espacios sin precio.
    INSERT INTO reserva_espacio (reserva_id, espacio_id, inicio, fin, tarifa_aplicada)
    SELECT p_reserva_id, t.espacio_id, v_inicio, v_fin, ta.valor
      FROM tmp_espacios_reserva t
      JOIN espacio e ON e.espacio_id = t.espacio_id
      JOIN tarifa ta ON ta.sede_id      = e.sede_id
                    AND ta.tipo_id      = e.tipo_id
                    AND ta.modalidad_id = p_modalidad_id;

    IF ROW_COUNT() < v_pedidos THEN
        -- reserva y los espacios que sí tenían tarifa ya están insertados
        SELECT e.codigo, te.nombre INTO v_codigo, v_tipo
          FROM tmp_espacios_reserva t
          JOIN espacio e       ON e.espacio_id = t.espacio_id
          JOIN tipo_espacio te ON te.tipo_id   = e.tipo_id
          LEFT JOIN tarifa ta  ON ta.sede_id      = e.sede_id
                              AND ta.tipo_id      = e.tipo_id
                              AND ta.modalidad_id = p_modalidad_id
         WHERE ta.valor IS NULL
         ORDER BY e.espacio_id
         LIMIT 1;
        SET v_msg = LEFT(CONCAT('El espacio ', v_codigo, ' (', v_tipo,
                                ') no tiene tarifa por ', v_modalidad, ' en su sede'), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- 3. Cruce con otras reservas vigentes del mismo espacio
    SELECT MIN(e.codigo) INTO v_codigo
      FROM reserva_espacio nuevo
      JOIN reserva_espacio otro ON otro.espacio_id  = nuevo.espacio_id
                               AND otro.reserva_id <> nuevo.reserva_id
                               AND otro.inicio      < nuevo.fin
                               AND otro.fin         > nuevo.inicio
      JOIN reserva r ON r.reserva_id = otro.reserva_id
      JOIN espacio e ON e.espacio_id = nuevo.espacio_id
     WHERE nuevo.reserva_id = p_reserva_id
       AND r.estado <> 'CANCELADA';

    IF v_codigo IS NOT NULL THEN
        SET v_msg = LEFT(CONCAT('El espacio ', v_codigo,
                                ' ya está reservado en un horario que se cruza'), 128);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- 4. Plan de cuotas: partes iguales y la última con el ajuste de
    --    centavos, para que sumen exactamente el valor de la reserva.
    SET v_valor = fn_valor_reserva(p_reserva_id);
    SET v_monto = ROUND(v_valor / p_num_cuotas, 2);
    SET i = 1;

    WHILE i <= p_num_cuotas DO
        INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
        VALUES (p_reserva_id, i,
                IF(i < p_num_cuotas, v_monto, v_valor - v_monto * (p_num_cuotas - 1)),
                NULL, NULL);
        SET i = i + 1;
    END WHILE;

    -- 5. Pago de la cuota 1 al reservar
    IF p_metodo_pago IS NOT NULL THEN
        UPDATE cuota
           SET fecha_pago = CURDATE(), metodo_pago = p_metodo_pago
         WHERE reserva_id = p_reserva_id AND num_cuota = 1;

        UPDATE reserva SET estado = 'CONFIRMADA' WHERE reserva_id = p_reserva_id;
    END IF;

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_espacios_reserva;
END$$


-- ============================================================
-- T3: sp_registrar_pago
-- ============================================================
--
-- Paga la siguiente cuota pendiente de una reserva, en orden de
-- num_cuota (clave parcial de la entidad débil).
--
-- Tablas que modifica: cuota (UPDATE o INSERT) y reserva (UPDATE).
--
-- Lógica con IF / ELSEIF:
--   - La reserva no existe, está CANCELADA o FINALIZADA -> error.
--   - Tiene una cuota sin pagar -> se paga la de menor número.
--   - No tiene cuotas (reservas PENDIENTES antiguas) -> se crea la
--     cuota 1 por el valor completo y se paga.
--   - Tiene todas pagadas -> error.
--   Después, si estaba PENDIENTE, pasa a CONFIRMADA.
--
-- Bloquea la reserva con FOR UPDATE: si llegan dos pagos al mismo
-- tiempo, el segundo espera y no paga dos veces la misma cuota.
--
-- Ejemplo:
--   CALL sp_registrar_pago(167, 'Nequi', @cuota, @monto);
--   SELECT @cuota, @monto, fn_saldo_pendiente(167);

CREATE PROCEDURE sp_registrar_pago(
    IN  p_reserva_id   INT,
    IN  p_metodo_pago  VARCHAR(30),
    OUT p_num_cuota    INT,
    OUT p_monto        DECIMAL(12,2)
)
BEGIN
    DECLARE v_msg     VARCHAR(128);
    DECLARE v_estado  VARCHAR(20);
    DECLARE v_cuotas  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_num_cuota = NULL;
        SET p_monto = NULL;
        RESIGNAL;
    END;

    SET p_num_cuota = NULL;
    SET p_monto = NULL;

    IF p_metodo_pago IS NULL OR p_metodo_pago NOT IN
       ('Efectivo', 'Tarjeta de crédito', 'Tarjeta débito', 'Transferencia', 'PSE', 'Nequi') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El método de pago debe ser Efectivo, Tarjeta de crédito, Tarjeta débito, Transferencia, PSE o Nequi';
    END IF;

    START TRANSACTION;

    SELECT estado INTO v_estado
      FROM reserva
     WHERE reserva_id = p_reserva_id
       FOR UPDATE;

    IF v_estado IS NULL THEN
        SET v_msg = CONCAT('La reserva ', IFNULL(p_reserva_id, 'NULL'), ' no existe');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF v_estado = 'CANCELADA' THEN
        SET v_msg = CONCAT('La reserva ', p_reserva_id, ' está cancelada y no admite pagos');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF v_estado = 'FINALIZADA' THEN
        SET v_msg = CONCAT('La reserva ', p_reserva_id, ' ya finalizó y está pagada');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    -- Menor cuota sin pagar (NULL si no hay) y total de cuotas
    SELECT MIN(CASE WHEN fecha_pago IS NULL THEN num_cuota END), COUNT(*)
      INTO p_num_cuota, v_cuotas
      FROM cuota
     WHERE reserva_id = p_reserva_id;

    IF p_num_cuota IS NOT NULL THEN
        -- Siguiente cuota del plan
        UPDATE cuota
           SET fecha_pago = CURDATE(), metodo_pago = p_metodo_pago
         WHERE reserva_id = p_reserva_id AND num_cuota = p_num_cuota;

        SELECT monto INTO p_monto
          FROM cuota WHERE reserva_id = p_reserva_id AND num_cuota = p_num_cuota;

    ELSEIF v_cuotas = 0 THEN
        -- Reserva sin plan de cuotas: un solo pago por el valor total
        SET p_num_cuota = 1;
        SET p_monto = fn_valor_reserva(p_reserva_id);

        INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
        VALUES (p_reserva_id, 1, p_monto, CURDATE(), p_metodo_pago);

    ELSE
        SET v_msg = CONCAT('La reserva ', p_reserva_id, ' ya tiene todas sus cuotas pagadas');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    IF v_estado = 'PENDIENTE' THEN
        UPDATE reserva SET estado = 'CONFIRMADA' WHERE reserva_id = p_reserva_id;
    END IF;

    COMMIT;
END$$


-- ============================================================
-- sp_cancelar_reserva
-- ============================================================
--
-- Cancela una reserva que todavía no tiene pagos. Al quedar
-- CANCELADA, sus espacios vuelven a estar disponibles en ese
-- horario (fn_espacio_disponible ya no la cuenta). Las cuotas sin
-- pagar se conservan como registro, igual que en los datos de
-- prueba.
--
-- Con IF / ELSEIF responde por qué no se puede cancelar: no existe,
-- ya está cancelada, ya finalizó, o tiene cuotas pagadas (una
-- reserva CANCELADA no puede tener pagos; ese caso requiere un
-- reembolso, que está fuera del alcance del sistema).
--
-- Ejemplo:
--   CALL sp_cancelar_reserva(167);

CREATE PROCEDURE sp_cancelar_reserva(IN p_reserva_id INT)
BEGIN
    DECLARE v_msg     VARCHAR(128);
    DECLARE v_estado  VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT estado INTO v_estado
      FROM reserva
     WHERE reserva_id = p_reserva_id
       FOR UPDATE;

    IF v_estado IS NULL THEN
        SET v_msg = CONCAT('La reserva ', IFNULL(p_reserva_id, 'NULL'), ' no existe');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF v_estado = 'CANCELADA' THEN
        SET v_msg = CONCAT('La reserva ', p_reserva_id, ' ya estaba cancelada');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF v_estado = 'FINALIZADA' THEN
        SET v_msg = CONCAT('La reserva ', p_reserva_id, ' ya finalizó y no se puede cancelar');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    ELSEIF EXISTS (SELECT 1 FROM cuota
                    WHERE reserva_id = p_reserva_id AND fecha_pago IS NOT NULL) THEN
        SET v_msg = CONCAT('La reserva ', p_reserva_id,
                           ' tiene pagos registrados; cancelarla requiere un reembolso');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    UPDATE reserva SET estado = 'CANCELADA' WHERE reserva_id = p_reserva_id;

    COMMIT;
END$$

DELIMITER ;
