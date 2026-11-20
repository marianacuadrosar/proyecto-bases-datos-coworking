-- ============================================================
-- PROCEDIMIENTOS DE APOYO PARA LA APLICACIÓN WEB
-- Caso 6: Red de espacios de coworking
-- ============================================================
--
-- Orden de ejecución: después de 07_procedimientos_funciones.sql y de
-- 10_vistas_union.sql, porque estos procedimientos leen sus vistas.
-- Se puede correr varias veces: cada procedimiento se borra y se crea.
--
-- La aplicación no escribe SQL: todo pasa por procedimientos.
--
-- Las operaciones principales usan los procedimientos del núcleo
-- (07_procedimientos_funciones.sql), con sus transacciones:
--   crear cliente      sp_registrar_cliente
--   crear reserva      sp_crear_reserva
--   registrar un pago  sp_registrar_pago
--   cancelar reserva   sp_cancelar_reserva
--
-- Este archivo agrega lo que la aplicación necesita y el núcleo no
-- tiene: las consultas para llenar las pantallas, editar y eliminar
-- clientes, finalizar y eliminar reservas. Todos usan el prefijo
-- sp_app_ para distinguirlos de los del núcleo.
--
-- Igual que en el núcleo, una entrada inválida (un id que no existe,
-- un borrado que rompería el historial) se responde con
-- SIGNAL SQLSTATE '45000' y un mensaje que la aplicación muestra tal
-- cual. Los que modifican más de una tabla usan transacción con
-- EXIT HANDLER, ROLLBACK y RESIGNAL.
--
-- Este script usa DELIMITER, así que se ejecuta desde MySQL Workbench
-- o con el cliente de consola: mysql -u root -p < sql/11_procedimientos_app.sql
-- ============================================================

SET NAMES utf8mb4;
USE coworking_db;

-- Versiones anteriores de este archivo, ya reemplazadas por el núcleo
DROP PROCEDURE IF EXISTS sp_app_registrar_cliente;
DROP PROCEDURE IF EXISTS sp_app_crear_reserva;
DROP PROCEDURE IF EXISTS sp_app_agregar_espacio;
DROP PROCEDURE IF EXISTS sp_app_pagar_cuota;
DROP PROCEDURE IF EXISTS sp_app_cambiar_estado;

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
    IN p_sede_id INT,
    IN p_tipo_id INT
)
BEGIN
    SELECT espacio_id, codigo, capacidad, sede_id, sede, ciudad, barrio,
           hora_apertura, hora_cierre, tipo_id, tipo, precio_hora, precio_dia
    FROM vw_espacio_catalogo
    WHERE (p_ciudad  IS NULL OR ciudad  = p_ciudad)
      AND (p_sede_id IS NULL OR sede_id = p_sede_id)
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
            SET MESSAGE_TEXT = 'El cliente no existe';
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


-- Actualiza el email y el nombre del cliente y, si viene, agrega un
-- teléfono. Modifica hasta tres tablas: cliente, su subclase y
-- telefono_cliente, por eso va en una transacción.
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
            SET MESSAGE_TEXT = 'El cliente no existe';
    END IF;

    IF p_email IS NULL OR NOT REGEXP_LIKE(p_email, '^[^@ ]+@[^@ ]+\\.[^@ ]+$') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El email no tiene un formato válido';
    END IF;

    IF p_telefono_nuevo IS NOT NULL
       AND NOT REGEXP_LIKE(p_telefono_nuevo, '^([0-9]{7}|[0-9]{10})$') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El teléfono debe tener 7 o 10 dígitos';
    END IF;

    IF (v_tipo = 'NATURAL' AND (p_nombres IS NULL OR p_apellidos IS NULL))
       OR (v_tipo = 'EMPRESA' AND (p_razon_social IS NULL OR p_nombre_contacto IS NULL)) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Faltan datos del nombre del cliente';
    END IF;

    START TRANSACTION;

    IF EXISTS (SELECT 1 FROM cliente
               WHERE email = p_email AND cliente_id <> p_cliente_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ese email ya lo usa otro cliente';
    END IF;

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

    -- Si el teléfono ya estaba registrado para este cliente, no se repite
    IF p_telefono_nuevo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM telefono_cliente
                       WHERE cliente_id = p_cliente_id AND telefono = p_telefono_nuevo) THEN
        INSERT INTO telefono_cliente (cliente_id, telefono)
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
    DECLARE v_mensaje VARCHAR(128);

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE cliente_id = p_cliente_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El cliente no existe';
    END IF;

    SELECT COUNT(*) INTO v_reservas
    FROM reserva
    WHERE cliente_id = p_cliente_id;

    IF v_reservas > 0 THEN
        SET v_mensaje = CONCAT('No se puede eliminar: el cliente tiene ', v_reservas,
                               ' reserva(s) registradas');
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
            SET MESSAGE_TEXT = 'La reserva no existe';
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


-- Marca una reserva CONFIRMADA como FINALIZADA cuando ya está pagada
-- por completo. Las demás transiciones de estado las hacen los
-- procedimientos del núcleo: pagar confirma y sp_cancelar_reserva cancela.
DROP PROCEDURE IF EXISTS sp_app_finalizar_reserva $$
CREATE PROCEDURE sp_app_finalizar_reserva(IN p_reserva_id INT)
BEGIN
    DECLARE v_estado VARCHAR(20);
    DECLARE v_mensaje VARCHAR(128);

    SELECT estado INTO v_estado
    FROM reserva
    WHERE reserva_id = p_reserva_id;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva no existe';
    ELSEIF v_estado <> 'CONFIRMADA' THEN
        SET v_mensaje = CONCAT('Solo se finaliza una reserva CONFIRMADA; esta está ', v_estado);
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje;
    ELSEIF fn_saldo_pendiente(p_reserva_id) > 0 THEN
        SET v_mensaje = CONCAT('No se puede finalizar: falta pagar ',
                               FORMAT(fn_saldo_pendiente(p_reserva_id), 0, 'es_CO'), ' pesos');
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_mensaje;
    END IF;

    UPDATE reserva
    SET estado = 'FINALIZADA'
    WHERE reserva_id = p_reserva_id;
END $$


-- Borra una reserva que no tiene pagos. Sus espacios y cuotas se
-- borran en cascada. Si ya hay pagos no se borra: el dinero recibido
-- debe quedar registrado.
DROP PROCEDURE IF EXISTS sp_app_eliminar_reserva $$
CREATE PROCEDURE sp_app_eliminar_reserva(IN p_reserva_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM reserva WHERE reserva_id = p_reserva_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva no existe';
    END IF;

    IF EXISTS (SELECT 1 FROM cuota
               WHERE reserva_id = p_reserva_id AND fecha_pago IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva tiene pagos registrados y no se puede eliminar';
    END IF;

    DELETE FROM reserva
    WHERE reserva_id = p_reserva_id;
END $$


DELIMITER ;
