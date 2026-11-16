-- ============================================================
-- PROYECTO FINAL - BASES DE DATOS
-- Caso 6: Red de espacios de coworking
-- Programa: Ingeniería Informática
-- ============================================================

DROP DATABASE IF EXISTS coworking_db;
CREATE DATABASE coworking_db;
USE coworking_db;

-- ============================================================
-- 1. CLIENTE
-- Supertipo de PERSONA_NATURAL y EMPRESA
-- ============================================================

CREATE TABLE cliente (
    cliente_id INT AUTO_INCREMENT,
    email VARCHAR(120) NOT NULL,
    fecha_registro DATE NOT NULL DEFAULT (CURRENT_DATE),

    CONSTRAINT pk_cliente
        PRIMARY KEY (cliente_id),

    CONSTRAINT uq_cliente_email
        UNIQUE (email)
);


-- ============================================================
-- 2. PERSONA NATURAL
-- Especialización de CLIENTE
-- ============================================================

CREATE TABLE persona_natural (
    cliente_id INT,
    nombres VARCHAR(80) NOT NULL,
    apellidos VARCHAR(80) NOT NULL,
    documento VARCHAR(30) NOT NULL,

    CONSTRAINT pk_persona_natural
        PRIMARY KEY (cliente_id),

    CONSTRAINT uq_persona_documento
        UNIQUE (documento),

    CONSTRAINT fk_persona_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(cliente_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);


-- ============================================================
-- 3. EMPRESA
-- Especialización de CLIENTE
-- ============================================================

CREATE TABLE empresa (
    cliente_id INT,
    razon_social VARCHAR(120) NOT NULL,
    nit VARCHAR(30) NOT NULL,

    CONSTRAINT pk_empresa
        PRIMARY KEY (cliente_id),

    CONSTRAINT uq_empresa_nit
        UNIQUE (nit),

    CONSTRAINT fk_empresa_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(cliente_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);


-- ============================================================
-- 4. TELEFONO CLIENTE
-- Surge del atributo multivaluado telefono
-- ============================================================

CREATE TABLE telefono_cliente (
    cliente_id INT,
    telefono VARCHAR(20),

    CONSTRAINT pk_telefono_cliente
        PRIMARY KEY (cliente_id, telefono),

    CONSTRAINT fk_telefono_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(cliente_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);


-- ============================================================
-- 5. SEDE
-- ============================================================

CREATE TABLE sede (
    sede_id INT AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    calle VARCHAR(150) NOT NULL,
    ciudad VARCHAR(80) NOT NULL,

    CONSTRAINT pk_sede
        PRIMARY KEY (sede_id),

    CONSTRAINT uq_sede_nombre_ciudad
        UNIQUE (nombre, ciudad)
);


-- ============================================================
-- 6. TIPO DE ESPACIO
-- ============================================================

CREATE TABLE tipo_espacio (
    tipo_espacio_id INT AUTO_INCREMENT,
    nombre_tipo VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200),

    CONSTRAINT pk_tipo_espacio
        PRIMARY KEY (tipo_espacio_id),

    CONSTRAINT uq_tipo_espacio_nombre
        UNIQUE (nombre_tipo)
);


-- ============================================================
-- 7. MODALIDAD DE RESERVA
-- ============================================================

CREATE TABLE modalidad_reserva (
    modalidad_id INT AUTO_INCREMENT,
    nombre_modalidad VARCHAR(20) NOT NULL,

    CONSTRAINT pk_modalidad_reserva
        PRIMARY KEY (modalidad_id),

    CONSTRAINT uq_modalidad_nombre
        UNIQUE (nombre_modalidad),

    CONSTRAINT ck_modalidad
        CHECK (nombre_modalidad IN ('HORA', 'DIA'))
);


-- ============================================================
-- 8. ESPACIO
-- ============================================================

CREATE TABLE espacio (
    espacio_id INT AUTO_INCREMENT,
    sede_id INT NOT NULL,
    tipo_espacio_id INT NOT NULL,
    codigo VARCHAR(30) NOT NULL,
    capacidad INT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'DISPONIBLE',

    CONSTRAINT pk_espacio
        PRIMARY KEY (espacio_id),

    CONSTRAINT fk_espacio_sede
        FOREIGN KEY (sede_id)
        REFERENCES sede(sede_id),

    CONSTRAINT fk_espacio_tipo
        FOREIGN KEY (tipo_espacio_id)
        REFERENCES tipo_espacio(tipo_espacio_id),

    CONSTRAINT uq_espacio_sede_codigo
        UNIQUE (sede_id, codigo),

    CONSTRAINT ck_espacio_capacidad
        CHECK (capacidad > 0),

    CONSTRAINT ck_espacio_estado
        CHECK (
            estado IN ('DISPONIBLE', 'MANTENIMIENTO', 'INACTIVO')
        )
);


-- ============================================================
-- 9. TARIFA
-- Relación ternaria:
-- SEDE + TIPO_ESPACIO + MODALIDAD_RESERVA
-- ============================================================

CREATE TABLE tarifa (
    sede_id INT,
    tipo_espacio_id INT,
    modalidad_id INT,
    valor_tarifa DECIMAL(12,2) NOT NULL,

    CONSTRAINT pk_tarifa
        PRIMARY KEY (
            sede_id,
            tipo_espacio_id,
            modalidad_id
        ),

    CONSTRAINT fk_tarifa_sede
        FOREIGN KEY (sede_id)
        REFERENCES sede(sede_id),

    CONSTRAINT fk_tarifa_tipo
        FOREIGN KEY (tipo_espacio_id)
        REFERENCES tipo_espacio(tipo_espacio_id),

    CONSTRAINT fk_tarifa_modalidad
        FOREIGN KEY (modalidad_id)
        REFERENCES modalidad_reserva(modalidad_id),

    CONSTRAINT ck_tarifa_valor
        CHECK (valor_tarifa > 0)
);


-- ============================================================
-- 10. RESERVA
-- ============================================================

CREATE TABLE reserva (
    reserva_id INT AUTO_INCREMENT,
    cliente_id INT NOT NULL,
    modalidad_id INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    hora_inicio TIME,
    hora_fin TIME,
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',

    CONSTRAINT pk_reserva
        PRIMARY KEY (reserva_id),

    CONSTRAINT fk_reserva_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(cliente_id),

    CONSTRAINT fk_reserva_modalidad
        FOREIGN KEY (modalidad_id)
        REFERENCES modalidad_reserva(modalidad_id),

    CONSTRAINT ck_reserva_fechas
        CHECK (fecha_fin >= fecha_inicio),

    CONSTRAINT ck_reserva_estado
        CHECK (
            estado IN (
                'PENDIENTE',
                'CONFIRMADA',
                'CANCELADA',
                'FINALIZADA'
            )
        )
);


-- ============================================================
-- 11. RESERVA ESPACIO
-- Entidad asociativa entre RESERVA y ESPACIO
-- ============================================================

CREATE TABLE reserva_espacio (
    reserva_id INT,
    espacio_id INT,

    CONSTRAINT pk_reserva_espacio
        PRIMARY KEY (reserva_id, espacio_id),

    CONSTRAINT fk_reserva_espacio_reserva
        FOREIGN KEY (reserva_id)
        REFERENCES reserva(reserva_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_reserva_espacio_espacio
        FOREIGN KEY (espacio_id)
        REFERENCES espacio(espacio_id)
);


-- ============================================================
-- 12. CUOTA
-- Entidad débil dependiente de RESERVA
-- ============================================================

CREATE TABLE cuota (
    reserva_id INT,
    numero_cuota INT,
    monto_pagado DECIMAL(12,2) NOT NULL,
    fecha_pago DATE,
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',

    CONSTRAINT pk_cuota
        PRIMARY KEY (reserva_id, numero_cuota),

    CONSTRAINT fk_cuota_reserva
        FOREIGN KEY (reserva_id)
        REFERENCES reserva(reserva_id)
        ON DELETE CASCADE,

    CONSTRAINT ck_numero_cuota
        CHECK (numero_cuota > 0),

    CONSTRAINT ck_monto_cuota
        CHECK (monto_pagado > 0),

    CONSTRAINT ck_estado_cuota
        CHECK (
            estado IN ('PENDIENTE', 'PAGADA')
        )
);
