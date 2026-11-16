-- ============================================================
-- PROYECTO FINAL - BASES DE DATOS
-- Caso 6: Red de espacios de coworking
-- Programa: Ingeniería Informática
-- ============================================================

DROP DATABASE IF EXISTS coworking_db;
CREATE DATABASE coworking_db;
USE coworking_db;


-- ============================================================
-- 1. SEDE
-- ============================================================

CREATE TABLE sede (
    sede_id INT AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    calle VARCHAR(150) NOT NULL,
    numero VARCHAR(10) NOT NULL,
    barrio VARCHAR(80) NOT NULL,
    ciudad VARCHAR(80) NOT NULL,
    hora_apertura TIME NOT NULL,
    hora_cierre TIME NOT NULL,

    CONSTRAINT pk_sede
        PRIMARY KEY (sede_id),

    CONSTRAINT ck_horario_sede
        CHECK (hora_cierre > hora_apertura)
);


-- ============================================================
-- 2. TIPO_ESPACIO
-- ============================================================

CREATE TABLE tipo_espacio (
    tipo_id INT AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(150),

    CONSTRAINT pk_tipo_espacio
        PRIMARY KEY (tipo_id),

    CONSTRAINT uq_tipo_espacio_nombre
        UNIQUE (nombre)
);


-- ============================================================
-- 3. MODALIDAD
-- ============================================================

CREATE TABLE modalidad (
    modalidad_id INT AUTO_INCREMENT,
    nombre VARCHAR(20) NOT NULL,

    CONSTRAINT pk_modalidad
        PRIMARY KEY (modalidad_id),

    CONSTRAINT uq_modalidad_nombre
        UNIQUE (nombre),

    CONSTRAINT ck_modalidad_nombre
        CHECK (nombre IN ('Hora', 'Dia'))
);


-- ============================================================
-- 4. CLIENTE
-- ============================================================

CREATE TABLE cliente (
    cliente_id INT AUTO_INCREMENT,
    email VARCHAR(100) NOT NULL,
    fecha_registro DATE NOT NULL DEFAULT (CURRENT_DATE),
    tipo_cliente VARCHAR(20) NOT NULL,

    CONSTRAINT pk_cliente
        PRIMARY KEY (cliente_id),

    CONSTRAINT ck_tipo_cliente
        CHECK (tipo_cliente IN ('NATURAL', 'EMPRESA'))
);


-- ============================================================
-- 5. TELEFONO_CLIENTE
-- Atributo multivaluado de CLIENTE
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
-- 6. PERSONA_NATURAL
-- Subclase de CLIENTE
-- ============================================================

CREATE TABLE persona_natural (
    cliente_id INT,
    documento VARCHAR(20) NOT NULL,
    nombres VARCHAR(60) NOT NULL,
    apellidos VARCHAR(60) NOT NULL,
    fecha_nacimiento DATE NOT NULL,

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
-- 7. EMPRESA
-- Subclase de CLIENTE
-- ============================================================

CREATE TABLE empresa (
    cliente_id INT,
    nit VARCHAR(15) NOT NULL,
    razon_social VARCHAR(120) NOT NULL,
    nombre_contacto VARCHAR(100) NOT NULL,

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
-- 8. ESPACIO
-- ============================================================

CREATE TABLE espacio (
    espacio_id INT AUTO_INCREMENT,
    codigo VARCHAR(100) NOT NULL,
    capacidad INT NOT NULL,
    sede_id INT NOT NULL,
    tipo_id INT NOT NULL,

    CONSTRAINT pk_espacio
        PRIMARY KEY (espacio_id),

    CONSTRAINT fk_espacio_sede
        FOREIGN KEY (sede_id)
        REFERENCES sede(sede_id),

    CONSTRAINT fk_espacio_tipo
        FOREIGN KEY (tipo_id)
        REFERENCES tipo_espacio(tipo_id),

    -- Dos espacios de una misma sede no pueden compartir código
    CONSTRAINT uq_espacio_sede_codigo
        UNIQUE (sede_id, codigo),

    CONSTRAINT ck_espacio_capacidad
        CHECK (capacidad > 0)
);


-- ============================================================
-- 9. TARIFA
-- Relación ternaria:
-- SEDE + TIPO_ESPACIO + MODALIDAD
-- ============================================================

CREATE TABLE tarifa (
    sede_id INT,
    tipo_id INT,
    modalidad_id INT,
    valor DECIMAL(12,2) NOT NULL,

    CONSTRAINT pk_tarifa
        PRIMARY KEY (
            sede_id,
            tipo_id,
            modalidad_id
        ),

    CONSTRAINT fk_tarifa_sede
        FOREIGN KEY (sede_id)
        REFERENCES sede(sede_id),

    CONSTRAINT fk_tarifa_tipo
        FOREIGN KEY (tipo_id)
        REFERENCES tipo_espacio(tipo_id),

    CONSTRAINT fk_tarifa_modalidad
        FOREIGN KEY (modalidad_id)
        REFERENCES modalidad(modalidad_id),

    CONSTRAINT ck_tarifa_valor
        CHECK (valor > 0)
);


-- ============================================================
-- 10. RESERVA
-- ============================================================

CREATE TABLE reserva (
    reserva_id INT AUTO_INCREMENT,
    fecha_creacion DATE NOT NULL DEFAULT (CURRENT_DATE),
    estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    cliente_id INT NOT NULL,
    modalidad_id INT NOT NULL,

    CONSTRAINT pk_reserva
        PRIMARY KEY (reserva_id),

    CONSTRAINT fk_reserva_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES cliente(cliente_id),

    CONSTRAINT fk_reserva_modalidad
        FOREIGN KEY (modalidad_id)
        REFERENCES modalidad(modalidad_id),

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
-- 11. RESERVA_ESPACIO
-- Entidad asociativa
-- ============================================================

CREATE TABLE reserva_espacio (
    reserva_id INT,
    espacio_id INT,
    inicio DATETIME NOT NULL,
    fin DATETIME NOT NULL,
    tarifa_aplicada DECIMAL(12,2) NOT NULL,

    CONSTRAINT pk_reserva_espacio
        PRIMARY KEY (reserva_id, espacio_id),

    CONSTRAINT fk_reserva_espacio_reserva
        FOREIGN KEY (reserva_id)
        REFERENCES reserva(reserva_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_reserva_espacio_espacio
        FOREIGN KEY (espacio_id)
        REFERENCES espacio(espacio_id),

    CONSTRAINT ck_reserva_espacio_fechas
        CHECK (fin > inicio),

    CONSTRAINT ck_tarifa_aplicada
        CHECK (tarifa_aplicada > 0)
);


-- ============================================================
-- 12. CUOTA
-- Entidad débil de RESERVA
-- ============================================================

CREATE TABLE cuota (
    reserva_id INT,
    num_cuota INT,
    monto DECIMAL(12,2) NOT NULL,
    fecha_pago DATE,
    metodo_pago VARCHAR(30),

    CONSTRAINT pk_cuota
        PRIMARY KEY (reserva_id, num_cuota),

    CONSTRAINT fk_cuota_reserva
        FOREIGN KEY (reserva_id)
        REFERENCES reserva(reserva_id)
        ON DELETE CASCADE,

    CONSTRAINT ck_num_cuota
        CHECK (num_cuota > 0),

    CONSTRAINT ck_cuota_monto
        CHECK (monto > 0)
);
