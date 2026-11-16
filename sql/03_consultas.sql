-- ============================================================
-- PROYECTO FINAL - BASES DE DATOS
-- BANCO DE CONSULTAS
-- Caso 6: Red de espacios de coworking
-- ============================================================

-- Cada consulta incluye:
-- 1. La pregunta de negocio que responde.
-- 2. La herramienta SQL utilizada.
-- 3. La justificación de por qué es apropiada.

-- ============================================================
-- SECCIÓN 1: WHERE / ORDER BY
-- ============================================================

-- Pregunta de negocio:
-- ¿Cuáles son las próximas reservas confirmadas?
--
-- Se utiliza WHERE para seleccionar únicamente las reservas
-- confirmadas y futuras. ORDER BY permite mostrarlas
-- cronológicamente para facilitar su gestión operativa.

SELECT
    reserva_id,
    cliente_id,
    fecha_inicio,
    hora_inicio,
    estado
FROM reserva
WHERE estado = 'CONFIRMADA'
  AND fecha_inicio >= CURRENT_DATE
ORDER BY fecha_inicio ASC, hora_inicio ASC;



-- Pregunta de negocio:
-- ¿Qué espacios se encuentran disponibles y cuáles tienen
-- mayor capacidad?
--
-- WHERE permite seleccionar únicamente los espacios
-- disponibles y ORDER BY permite priorizar aquellos
-- que tienen mayor capacidad.

SELECT
    espacio_id,
    sede_id,
    codigo,
    capacidad,
    estado
FROM espacio
WHERE estado = 'DISPONIBLE'
ORDER BY capacidad DESC;

-- Pregunta de negocio:
-- ¿Cuáles son las cuotas pendientes de mayor valor?
--
-- WHERE permite identificar únicamente las cuotas pendientes
-- y ORDER BY organiza primero aquellas de mayor valor.

SELECT
    reserva_id,
    numero_cuota,
    monto_pagado,
    fecha_pago,
    estado
FROM cuota
WHERE estado = 'PENDIENTE'
ORDER BY monto_pagado DESC;

-- ============================================================
-- SECCIÓN 2: UPDATE
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se confirma una reserva que actualmente está pendiente?
--
-- UPDATE se utiliza porque se modifica el estado de un
-- registro ya existente sin crear una nueva reserva.

UPDATE reserva
SET estado = 'CONFIRMADA'
WHERE reserva_id = 25
  AND estado = 'PENDIENTE';

-- Pregunta de negocio:
-- ¿Cómo se actualiza una tarifa cuando cambia el precio
-- establecido para una combinación específica?
--
-- UPDATE permite modificar el precio conservando la misma
-- combinación de sede, tipo de espacio y modalidad.

UPDATE tarifa
SET valor_tarifa = 85000.00
WHERE sede_id = 2
  AND tipo_espacio_id = 1
  AND modalidad_id = 2;

-- Pregunta de negocio:
-- ¿Cómo se marca un espacio temporalmente fuera de servicio
-- cuando debe entrar a mantenimiento?
--
-- UPDATE es apropiado porque el espacio continúa existiendo,
-- pero cambia su estado operacional.

UPDATE espacio
SET estado = 'MANTENIMIENTO'
WHERE espacio_id = 18
  AND estado = 'DISPONIBLE';

-- ============================================================
-- SECCIÓN 3: DELETE
-- ============================================================

-- Pregunta de negocio:
-- ¿Cómo se elimina un teléfono que un cliente ya no utiliza?
--
-- DELETE se utiliza porque ese número de contacto debe dejar
-- de formar parte de la información asociada al cliente.

DELETE FROM telefono_cliente
WHERE cliente_id = 15
  AND telefono = '3001234567';

-- Pregunta de negocio:
-- ¿Cómo se retira un espacio de una reserva sin eliminar
-- ni el espacio ni la reserva?
--
-- DELETE elimina únicamente el registro de la entidad
-- asociativa RESERVA_ESPACIO.

DELETE FROM reserva_espacio
WHERE reserva_id = 40
  AND espacio_id = 12;

-- Pregunta de negocio:
-- ¿Cómo se elimina una tarifa que dejó de ofrecerse?
--
-- DELETE se utiliza porque esa combinación específica
-- deja de estar disponible comercialmente.

DELETE FROM tarifa
WHERE sede_id = 3
  AND tipo_espacio_id = 2
  AND modalidad_id = 1;

