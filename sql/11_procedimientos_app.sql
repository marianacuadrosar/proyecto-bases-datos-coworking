-- ============================================================
-- PROCEDIMIENTOS DE LA APLICACIÓN WEB
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: después de 10_vistas_union.sql, porque varios
-- procedimientos leen las vistas de ese archivo.
-- Se puede correr varias veces: cada procedimiento se borra y se crea.
--
-- La aplicación no escribe SQL: todo lo que hace pasa por estos
-- procedimientos (prefijo sp_app_). Cada uno que modifica datos:
--   1. valida la entrada y, si algo está mal, responde con
--      SIGNAL SQLSTATE '45000' y un mensaje para el usuario;
--   2. abre su propia transacción;
--   3. si cualquier instrucción falla, el EXIT HANDLER hace ROLLBACK
--      y devuelve el error a la aplicación (RESIGNAL).
-- Así una operación se guarda completa o no se guarda nada, sin que
-- la aplicación tenga que manejar la transacción.
--
-- Los dos flujos transaccionales principales son:
--   sp_app_crear_reserva     -> RESERVA + RESERVA_ESPACIO + CUOTA
--   sp_app_registrar_cliente -> CLIENTE + PERSONA_NATURAL o EMPRESA
--                               + TELEFONO_CLIENTE
--
-- Este script usa DELIMITER, así que se ejecuta desde MySQL Workbench
-- o con el cliente de consola (mysql ... < 11_procedimientos_app.sql).
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;

DELIMITER $$


-- ============================================================
-- CATÁLOGOS
-- ============================================================

-- Listas para llenar los formularios: modalidades, tipos y ciudades.
DROP PROCEDURE IF EXISTS sp_app_listar_catalogos $$
CREATE PROCEDURE sp_app_listar_catalogos()
BEGIN
    SELECT modalidad_id, nombre FROM modalidad ORDER BY modalidad_id;
    SELECT tipo_id, nombre FROM tipo_espacio ORDER BY nombre;
    SELECT DISTINCT ciudad FROM sede ORDER BY ciudad;
END $$


-- Catálogo de espacios. NULL en un filtro significa "sin filtrar".
DROP PROCEDURE IF EXISTS sp_app_listar_espacios $$
CREATE PROCEDURE sp_app_listar_espacios(
    IN p_ciudad  VARCHAR(80),
    IN p_tipo_id INT
)
BEGIN
    SELECT espacio_id, codigo, capacidad, sede_id, sede, ciudad, barrio,
           hora_apertura, hora_cierre, tipo_id, tipo, precio_hora, precio_dia
    FROM vw_espacio_catalogo
    WHERE (p_ciudad IS NULL OR ciudad = p_ciudad)
      AND (p_tipo_id IS NULL OR tipo_id = p_tipo_id)
    ORDER BY ciudad, sede, tipo, codigo;
END $$


-- ============================================================
-- CLIENTES
-- ============================================================

-- Busca por nombre, email o documento/NIT. Vacío = todos.
DROP PROCEDURE IF EXISTS sp_app_listar_clientes $$
CREATE PROCEDURE sp_app_listar_clientes(IN p_buscar VARCHAR(100))
BEGIN
    SELECT cliente_id, tipo_cliente, nombre, identificacion, email,
           telefonos, total_reservas
    FROM vw_cliente_detalle
    WHERE p_buscar IS NULL OR p_buscar = ''
       OR nombre         LIKE CONCAT('%', p_buscar, '%')
       OR email          LIKE CONCAT('%', p_buscar, '%')
       OR identificacion LIKE CONCAT('%', p_buscar, '%')
    ORDER BY nombre;
END $$


-- Devuelve dos resultados: los datos del cliente y sus teléfonos.
DROP PROCEDURE IF EXISTS sp_app_obtener_cliente $$
CREATE PROCEDURE sp_app_obtener_cliente(IN p_cliente_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cliente_id = p_cliente_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente no existe.';
    END IF;

    SELECT c.cliente_id, c.tipo_cliente, c.email, c.fecha_registro,
           p.documento, p.nombres, p.apellidos, p.fecha_nacimiento,
           e.nit, e.razon_social, e.nombre_contacto
    FROM cliente c
    LEFT JOIN persona_natural p ON p.cliente_id = c.cliente_id
    LEFT JOIN empresa e         ON e.cliente_id = c.cliente_id
    WHERE c.cliente_id = p_cliente_id;

    SELECT telefono
    FROM telefono_cliente
    WHERE cliente_id = p_cliente_id
    ORDER BY telefono;
END $$


-- FLUJO TRANSACCIONAL 2: registrar un cliente.
-- Inserta en CLIENTE, en su subclase y en TELEFONO_CLIENTE. Si el
-- documento o el NIT ya existen, el INSERT de la subclase falla
-- después de haber insertado en CLIENTE; el ROLLBACK deshace ese
-- primer INSERT para que no quede un cliente sin subclase.
DROP PROCEDURE IF EXISTS sp_app_registrar_cliente $$
CREATE PROCEDURE sp_app_registrar_cliente(
    IN  p_tipo_cliente     VARCHAR(20),
    IN  p_email            VARCHAR(100),
    IN  p_telefono         VARCHAR(20),
    IN  p_documento        VARCHAR(20),
    IN  p_nombres          VARCHAR(60),
    IN  p_apellidos        VARCHAR(60),
    IN  p_fecha_nacimiento DATE,
    IN  p_nit              VARCHAR(15),
    IN  p_razon_social     VARCHAR(120),
    IN  p_nombre_contacto  VARCHAR(100),
    OUT p_cliente_id       INT
)
BEGIN
    -- 1062 = valor repetido en una columna UNIQUE (documento o NIT).
    DECLARE EXIT HANDLER FOR 1062
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El documento o NIT ya está registrado en otro cliente. No se guardó ningún dato.';
    END;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_tipo_cliente NOT IN ('NATURAL', 'EMPRESA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El tipo de cliente debe ser NATURAL o EMPRESA.';
    END IF;

    IF EXISTS (SELECT 1 FROM cliente WHERE email = p_email) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya existe un cliente con ese email.';
    END IF;

    START TRANSACTION;

    INSERT INTO cliente (email, tipo_cliente)
    VALUES (p_email, p_tipo_cliente);

    SET p_cliente_id = LAST_INSERT_ID();

    IF p_tipo_cliente = 'NATURAL' THEN
        INSERT INTO persona_natural (cliente_id, documento, nombres, apellidos, fecha_nacimiento)
        VALUES (p_cliente_id, p_documento, p_nombres, p_apellidos, p_fecha_nacimiento);
    ELSE
        INSERT INTO empresa (cliente_id, nit, razon_social, nombre_contacto)
        VALUES (p_cliente_id, p_nit, p_razon_social, p_nombre_contacto);
    END IF;

    INSERT INTO telefono_cliente (cliente_id, telefono)
    VALUES (p_cliente_id, p_telefono);

    COMMIT;
END $$


-- Actualiza email y nombre del cliente y, si viene, agrega un teléfono.
-- Los datos que no aplican al tipo de cliente se ignoran.
DROP PROCEDURE IF EXISTS sp_app_actualizar_cliente $$
CREATE PROCEDURE sp_app_actualizar_cliente(
    IN p_cliente_id      INT,
    IN p_email           VARCHAR(100),
    IN p_nombres         VARCHAR(60),
    IN p_apellidos       VARCHAR(60),
    IN p_razon_social    VARCHAR(120),
    IN p_nombre_contacto VARCHAR(100),
    IN p_telefono_nuevo  VARCHAR(20)
)
BEGIN
    DECLARE v_tipo VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT tipo_cliente INTO v_tipo
    FROM cliente
    WHERE cliente_id = p_cliente_id;

    IF v_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente no existe.';
    END IF;

    IF EXISTS (SELECT 1 FROM cliente
               WHERE email = p_email AND cliente_id <> p_cliente_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ese email ya lo usa otro cliente.';
    END IF;

    START TRANSACTION;

    UPDATE cliente
    SET email = p_email
    WHERE cliente_id = p_cliente_id;

    IF v_tipo = 'NATURAL' THEN
        UPDATE persona_natural
        SET nombres = p_nombres, apellidos = p_apellidos
        WHERE cliente_id = p_cliente_id;
    ELSE
        UPDATE empresa
        SET razon_social = p_razon_social, nombre_contacto = p_nombre_contacto
        WHERE cliente_id = p_cliente_id;
    END IF;

    IF p_telefono_nuevo IS NOT NULL AND p_telefono_nuevo <> '' THEN
        INSERT IGNORE INTO telefono_cliente (cliente_id, telefono)
        VALUES (p_cliente_id, p_telefono_nuevo);
    END IF;

    COMMIT;
END $$


-- Borra un cliente sin reservas. Sus teléfonos y su subclase se
-- borran en cascada. Si tiene reservas no se borra, para no perder
-- el historial de pagos.
DROP PROCEDURE IF EXISTS sp_app_eliminar_cliente $$
CREATE PROCEDURE sp_app_eliminar_cliente(IN p_cliente_id INT)
BEGIN
    DECLARE v_reservas INT;
    DECLARE v_mensaje VARCHAR(200);

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cliente_id = p_cliente_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente no existe.';
    END IF;

    SELECT COUNT(*) INTO v_reservas
    FROM reserva
    WHERE cliente_id = p_cliente_id;

    IF v_reservas > 0 THEN
        SET v_mensaje = CONCAT('No se puede eliminar: el cliente tiene ', v_reservas,
                               ' reserva(s) registradas.');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje;
    END IF;

    DELETE FROM cliente
    WHERE cliente_id = p_cliente_id;
END $$


-- ============================================================
-- RESERVAS
-- ============================================================

-- Lista de reservas con su valor y saldo. Filtros opcionales por
-- estado y por cliente. Muestra las 200 más recientes.
DROP PROCEDURE IF EXISTS sp_app_listar_reservas $$
CREATE PROCEDURE sp_app_listar_reservas(
    IN p_estado     VARCHAR(20),
    IN p_cliente_id INT
)
BEGIN
    SELECT reserva_id, fecha_creacion, estado, modalidad, cliente_id, cliente,
           sede, ciudad, espacios, inicio, fin, valor_total, pagado, saldo
    FROM vw_reserva_resumen
    WHERE (p_estado IS NULL OR p_estado = '' OR estado = p_estado)
      AND (p_cliente_id IS NULL OR cliente_id = p_cliente_id)
    ORDER BY reserva_id DESC
    LIMIT 200;
END $$


-- Devuelve tres resultados: el resumen, los espacios y las cuotas.
DROP PROCEDURE IF EXISTS sp_app_detalle_reserva $$
CREATE PROCEDURE sp_app_detalle_reserva(IN p_reserva_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM reserva WHERE reserva_id = p_reserva_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva no existe.';
    END IF;

    SELECT reserva_id, fecha_creacion, estado, modalidad, cliente_id, cliente,
           sede, ciudad, espacios, inicio, fin, valor_total, pagado, saldo
    FROM vw_reserva_resumen
    WHERE reserva_id = p_reserva_id;

    SELECT re.espacio_id, e.codigo, te.nombre AS tipo, e.capacidad,
           re.inicio, re.fin, re.tarifa_aplicada,
           ROUND(re.tarifa_aplicada *
                 CASE WHEN m.nombre = 'Hora'
                      THEN TIMESTAMPDIFF(MINUTE, re.inicio, re.fin) / 60
                      ELSE 1
                 END, 2) AS subtotal
    FROM reserva_espacio re
    INNER JOIN reserva r       ON r.reserva_id   = re.reserva_id
    INNER JOIN modalidad m     ON m.modalidad_id = r.modalidad_id
    INNER JOIN espacio e       ON e.espacio_id   = re.espacio_id
    INNER JOIN tipo_espacio te ON te.tipo_id     = e.tipo_id
    WHERE re.reserva_id = p_reserva_id
    ORDER BY e.codigo;

    SELECT num_cuota, monto, fecha_pago, metodo_pago
    FROM cuota
    WHERE reserva_id = p_reserva_id
    ORDER BY num_cuota;
END $$


-- Paso interno de sp_app_crear_reserva (la aplicación no lo llama).
-- Valida un espacio y lo agrega a la reserva con la tarifa vigente.
-- Si algo falla lanza SIGNAL; el error sube a sp_app_crear_reserva,
-- cuyo handler hace ROLLBACK de toda la reserva.
DROP PROCEDURE IF EXISTS sp_app_agregar_espacio $$
CREATE PROCEDURE sp_app_agregar_espacio(
    IN p_reserva_id   INT,
    IN p_espacio_id   INT,
    IN p_sede_id      INT,
    IN p_modalidad_id INT,
    IN p_inicio       DATETIME,
    IN p_fin          DATETIME
)
BEGIN
    DECLARE v_sede_espacio INT;
    DECLARE v_tarifa DECIMAL(12,2);
    DECLARE v_mensaje VARCHAR(200);

    SELECT sede_id INTO v_sede_espacio
    FROM espacio
    WHERE espacio_id = p_espacio_id;

    IF v_sede_espacio IS NULL THEN
        SET v_mensaje = CONCAT('El espacio ', p_espacio_id, ' no existe.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF v_sede_espacio <> p_sede_id THEN
        SET v_mensaje = CONCAT('El espacio ', p_espacio_id,
                               ' es de otra sede. Todos los espacios de una reserva deben ser de la misma sede.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    IF EXISTS (SELECT 1 FROM reserva_espacio
               WHERE reserva_id = p_reserva_id AND espacio_id = p_espacio_id) THEN
        SET v_mensaje = CONCAT('El espacio ', p_espacio_id, ' está repetido en la reserva.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    -- Dos reservas se cruzan si una empieza antes de que la otra termine
    -- y termina después de que la otra empieza.
    IF EXISTS (SELECT 1
               FROM reserva_espacio re
               INNER JOIN reserva r ON r.reserva_id = re.reserva_id
               WHERE re.espacio_id = p_espacio_id
                 AND r.estado <> 'CANCELADA'
                 AND re.inicio < p_fin
                 AND re.fin > p_inicio) THEN
        SET v_mensaje = CONCAT('El espacio ', p_espacio_id,
                               ' ya está reservado en ese horario. No se guardó la reserva.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    SELECT t.valor INTO v_tarifa
    FROM tarifa t
    INNER JOIN espacio e ON e.sede_id = t.sede_id AND e.tipo_id = t.tipo_id
    WHERE e.espacio_id = p_espacio_id
      AND t.modalidad_id = p_modalidad_id;

    IF v_tarifa IS NULL THEN
        SET v_mensaje = CONCAT('El espacio ', p_espacio_id,
                               ' no tiene tarifa para esa modalidad en su sede.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    INSERT INTO reserva_espacio (reserva_id, espacio_id, inicio, fin, tarifa_aplicada)
    VALUES (p_reserva_id, p_espacio_id, p_inicio, p_fin, v_tarifa);
END $$


-- FLUJO TRANSACCIONAL 1: crear una reserva.
-- Inserta en RESERVA, en RESERVA_ESPACIO (uno a tres espacios) y en
-- CUOTA. Todos los espacios comparten fecha y horario. Por día, el
-- horario es el de la sede completo.
--   - Con anticipo: cuota 1 pagada hoy, cuota 2 con el saldo y la
--     reserva queda CONFIRMADA.
--   - Sin anticipo: una sola cuota sin pagar por el total y la reserva
--     queda PENDIENTE.
-- Si un espacio está ocupado, no tiene tarifa o el anticipo supera el
-- total, se hace ROLLBACK y no queda nada guardado.
DROP PROCEDURE IF EXISTS sp_app_crear_reserva $$
CREATE PROCEDURE sp_app_crear_reserva(
    IN  p_cliente_id   INT,
    IN  p_modalidad_id INT,
    IN  p_fecha        DATE,
    IN  p_hora_inicio  TIME,
    IN  p_hora_fin     TIME,
    IN  p_espacio_1    INT,
    IN  p_espacio_2    INT,
    IN  p_espacio_3    INT,
    IN  p_anticipo     DECIMAL(12,2),
    IN  p_metodo_pago  VARCHAR(30),
    OUT p_reserva_id   INT
)
BEGIN
    DECLARE v_modalidad VARCHAR(20);
    DECLARE v_sede_id INT;
    DECLARE v_apertura TIME;
    DECLARE v_cierre TIME;
    DECLARE v_inicio DATETIME;
    DECLARE v_fin DATETIME;
    DECLARE v_total DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Validaciones que no necesitan escribir nada.
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cliente_id = p_cliente_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El cliente no existe.';
    END IF;

    SELECT nombre INTO v_modalidad
    FROM modalidad
    WHERE modalidad_id = p_modalidad_id;

    IF v_modalidad IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La modalidad no existe.';
    END IF;

    IF p_fecha IS NULL OR p_fecha < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la reserva no puede ser anterior a hoy.';
    END IF;

    IF p_espacio_1 IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva debe incluir al menos un espacio.';
    END IF;

    SELECT s.sede_id, s.hora_apertura, s.hora_cierre
      INTO v_sede_id, v_apertura, v_cierre
    FROM espacio e
    INNER JOIN sede s ON s.sede_id = e.sede_id
    WHERE e.espacio_id = p_espacio_1;

    IF v_sede_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El primer espacio no existe.';
    END IF;

    IF v_modalidad = 'Dia' THEN
        SET v_inicio = TIMESTAMP(p_fecha, v_apertura);
        SET v_fin    = TIMESTAMP(p_fecha, v_cierre);
    ELSE
        IF p_hora_inicio IS NULL OR p_hora_fin IS NULL OR p_hora_fin <= p_hora_inicio THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Por hora se necesita una hora de inicio y una de fin posterior.';
        END IF;
        IF p_hora_inicio < v_apertura OR p_hora_fin > v_cierre THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'El horario está fuera del horario de atención de la sede.';
        END IF;
        SET v_inicio = TIMESTAMP(p_fecha, p_hora_inicio);
        SET v_fin    = TIMESTAMP(p_fecha, p_hora_fin);
    END IF;

    IF p_anticipo IS NULL OR p_anticipo < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El anticipo no puede ser negativo.';
    END IF;

    IF p_anticipo > 0 AND (p_metodo_pago IS NULL OR p_metodo_pago = '') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Indique el método de pago del anticipo.';
    END IF;

    START TRANSACTION;

    INSERT INTO reserva (cliente_id, modalidad_id, estado)
    VALUES (p_cliente_id, p_modalidad_id, 'PENDIENTE');

    SET p_reserva_id = LAST_INSERT_ID();

    CALL sp_app_agregar_espacio(p_reserva_id, p_espacio_1, v_sede_id, p_modalidad_id, v_inicio, v_fin);

    IF p_espacio_2 IS NOT NULL THEN
        CALL sp_app_agregar_espacio(p_reserva_id, p_espacio_2, v_sede_id, p_modalidad_id, v_inicio, v_fin);
    END IF;

    IF p_espacio_3 IS NOT NULL THEN
        CALL sp_app_agregar_espacio(p_reserva_id, p_espacio_3, v_sede_id, p_modalidad_id, v_inicio, v_fin);
    END IF;

    SELECT valor_total INTO v_total
    FROM vw_reserva_resumen
    WHERE reserva_id = p_reserva_id;

    IF p_anticipo > v_total THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El anticipo no puede superar el valor total de la reserva. No se guardó la reserva.';
    END IF;

    IF p_anticipo > 0 THEN
        INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
        VALUES (p_reserva_id, 1, p_anticipo, CURDATE(), p_metodo_pago);

        IF v_total > p_anticipo THEN
            INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
            VALUES (p_reserva_id, 2, v_total - p_anticipo, NULL, NULL);
        END IF;

        UPDATE reserva
        SET estado = 'CONFIRMADA'
        WHERE reserva_id = p_reserva_id;
    ELSE
        INSERT INTO cuota (reserva_id, num_cuota, monto, fecha_pago, metodo_pago)
        VALUES (p_reserva_id, 1, v_total, NULL, NULL);
    END IF;

    COMMIT;
END $$


-- Registra el pago de una cuota. Si la reserva estaba PENDIENTE,
-- con el primer pago pasa a CONFIRMADA (CUOTA + RESERVA).
DROP PROCEDURE IF EXISTS sp_app_pagar_cuota $$
CREATE PROCEDURE sp_app_pagar_cuota(
    IN p_reserva_id  INT,
    IN p_num_cuota   INT,
    IN p_metodo_pago VARCHAR(30)
)
BEGIN
    DECLARE v_estado VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT estado INTO v_estado
    FROM reserva
    WHERE reserva_id = p_reserva_id;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe.';
    END IF;

    IF v_estado = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva está cancelada; no recibe pagos.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM cuota
                   WHERE reserva_id = p_reserva_id AND num_cuota = p_num_cuota) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cuota no existe.';
    END IF;

    IF EXISTS (SELECT 1 FROM cuota
               WHERE reserva_id = p_reserva_id AND num_cuota = p_num_cuota
                 AND fecha_pago IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esa cuota ya estaba pagada.';
    END IF;

    START TRANSACTION;

    UPDATE cuota
    SET fecha_pago = CURDATE(), metodo_pago = p_metodo_pago
    WHERE reserva_id = p_reserva_id AND num_cuota = p_num_cuota;

    IF v_estado = 'PENDIENTE' THEN
        UPDATE reserva
        SET estado = 'CONFIRMADA'
        WHERE reserva_id = p_reserva_id;
    END IF;

    COMMIT;
END $$


-- Cambia el estado de una reserva respetando las reglas del negocio.
-- Al cancelar se borran las cuotas sin pagar (ya no se van a cobrar);
-- las pagadas se conservan como registro.
DROP PROCEDURE IF EXISTS sp_app_cambiar_estado $$
CREATE PROCEDURE sp_app_cambiar_estado(
    IN p_reserva_id INT,
    IN p_estado     VARCHAR(20)
)
BEGIN
    DECLARE v_actual VARCHAR(20);
    DECLARE v_mensaje VARCHAR(200);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT estado INTO v_actual
    FROM reserva
    WHERE reserva_id = p_reserva_id;

    IF v_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe.';
    ELSEIF v_actual IN ('CANCELADA', 'FINALIZADA') THEN
        SET v_mensaje = CONCAT('La reserva ya está ', v_actual, ' y no puede cambiar de estado.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    ELSEIF p_estado = v_actual THEN
        SET v_mensaje = CONCAT('La reserva ya está ', v_actual, '.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    ELSEIF p_estado = 'CONFIRMADA'
       AND NOT EXISTS (SELECT 1 FROM cuota
                       WHERE reserva_id = p_reserva_id AND fecha_pago IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Para confirmar la reserva primero registre un pago.';
    ELSEIF p_estado = 'FINALIZADA'
       AND EXISTS (SELECT 1 FROM cuota
                   WHERE reserva_id = p_reserva_id AND fecha_pago IS NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede finalizar: la reserva tiene cuotas sin pagar.';
    ELSEIF p_estado NOT IN ('CONFIRMADA', 'CANCELADA', 'FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El estado nuevo debe ser CONFIRMADA, CANCELADA o FINALIZADA.';
    END IF;

    START TRANSACTION;

    UPDATE reserva
    SET estado = p_estado
    WHERE reserva_id = p_reserva_id;

    IF p_estado = 'CANCELADA' THEN
        DELETE FROM cuota
        WHERE reserva_id = p_reserva_id AND fecha_pago IS NULL;
    END IF;

    COMMIT;
END $$


-- Borra una reserva que no tiene pagos. Sus espacios y cuotas se
-- borran en cascada. Si ya hay pagos, se debe cancelar, no borrar.
DROP PROCEDURE IF EXISTS sp_app_eliminar_reserva $$
CREATE PROCEDURE sp_app_eliminar_reserva(IN p_reserva_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM reserva WHERE reserva_id = p_reserva_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva no existe.';
    END IF;

    IF EXISTS (SELECT 1 FROM cuota
               WHERE reserva_id = p_reserva_id AND fecha_pago IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva tiene pagos registrados: cancélela en lugar de eliminarla.';
    END IF;

    DELETE FROM reserva
    WHERE reserva_id = p_reserva_id;
END $$


DELIMITER ;
