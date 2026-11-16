-- ============================================================
-- PERSONA 1
-- BANCO DE CONSULTAS
-- Caso 6: Red de espacios de coworking
-- ============================================================


-- ============================================================
-- CONSULTA 1 - WHERE / ORDER BY
-- Reservas confirmadas ordenadas por fecha de creación
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuáles son las reservas confirmadas más recientemente creadas?
--
-- Justificación:
-- WHERE permite seleccionar únicamente las reservas que se
-- encuentran confirmadas y ORDER BY permite mostrar primero
-- las registradas más recientemente.

SELECT
    reserva_id,
    cliente_id,
    fecha_creacion,
    modalidad_id,
    estado
FROM reserva
WHERE estado = 'CONFIRMADA'
ORDER BY fecha_creacion DESC;


-- ============================================================
-- CONSULTA 2 - WHERE / ORDER BY
-- Espacios con capacidad mínima
-- ============================================================

-- Pregunta de negocio:
-- ¿Qué espacios tienen capacidad para seis o más personas
-- y cuáles ofrecen mayor capacidad?
--
-- Justificación:
-- WHERE permite filtrar los espacios que cumplen con una
-- capacidad mínima y ORDER BY permite priorizar aquellos
-- que pueden recibir más personas.

SELECT
    espacio_id,
    codigo,
    capacidad,
    sede_id,
    tipo_id
FROM espacio
WHERE capacidad >= 6
ORDER BY capacidad DESC, codigo ASC;


-- ============================================================
-- CONSULTA 3 - WHERE / ORDER BY
-- Cuotas sin fecha de pago
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuáles son las cuotas que todavía no tienen una fecha
-- de pago registrada y cuáles representan los mayores montos?
--
-- Justificación:
-- WHERE permite identificar las cuotas sin pago registrado
-- mediante IS NULL y ORDER BY permite mostrar primero las
-- de mayor monto.

SELECT
    reserva_id,
    num_cuota,
    monto,
    fecha_pago,
    metodo_pago
FROM cuota
WHERE fecha_pago IS NULL
ORDER BY monto DESC;


-- ============================================================
-- CONSULTA 4 - UPDATE
-- Confirmar una reserva pendiente
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se cambia una reserva de estado PENDIENTE
-- a CONFIRMADA?
--
-- Justificación:
-- UPDATE permite modificar el estado de una reserva ya
-- existente sin crear un nuevo registro.

UPDATE reserva
SET estado = 'CONFIRMADA'
WHERE reserva_id = 25
  AND estado = 'PENDIENTE';


-- ============================================================
-- CONSULTA 5 - UPDATE
-- Actualizar una tarifa
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se actualiza el precio de una combinación específica
-- de sede, tipo de espacio y modalidad?
--
-- Justificación:
-- UPDATE es adecuado porque la combinación tarifaria ya
-- existe y únicamente cambia el valor asociado.

UPDATE tarifa
SET valor = 85000.00
WHERE sede_id = 2
  AND tipo_id = 1
  AND modalidad_id = 2;


-- ============================================================
-- CONSULTA 6 - UPDATE
-- Actualizar capacidad de un espacio
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se actualiza la capacidad registrada de un espacio
-- después de una modificación física o redistribución?
--
-- Justificación:
-- UPDATE permite modificar uno de los atributos del espacio
-- sin cambiar su identidad ni crear un nuevo registro.

UPDATE espacio
SET capacidad = 10
WHERE espacio_id = 18;


-- ============================================================
-- CONSULTA 7 - DELETE
-- Eliminar un teléfono de un cliente
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se elimina un número de teléfono que un cliente
-- ya no utiliza?
--
-- Justificación:
-- DELETE permite eliminar únicamente el número de contacto,
-- sin eliminar al cliente ni sus demás datos.

DELETE FROM telefono_cliente
WHERE cliente_id = 15
  AND telefono = '3001234567';


-- ============================================================
-- CONSULTA 8 - DELETE
-- Retirar un espacio de una reserva
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se elimina un espacio específico de una reserva
-- sin eliminar ni la reserva ni el espacio?
--
-- Justificación:
-- DELETE elimina únicamente la fila de la entidad asociativa
-- RESERVA_ESPACIO que conecta ambas entidades.

DELETE FROM reserva_espacio
WHERE reserva_id = 40
  AND espacio_id = 12;


-- ============================================================
-- CONSULTA 9 - DELETE
-- Eliminar una tarifa que deja de ofrecerse
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se elimina una combinación tarifaria que deja
-- de formar parte de la oferta comercial?
--
-- Justificación:
-- DELETE es apropiado porque se elimina una combinación
-- completa de sede, tipo de espacio y modalidad.

DELETE FROM tarifa
WHERE sede_id = 3
  AND tipo_id = 2
  AND modalidad_id = 1;
