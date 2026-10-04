## CLIENTE

Representa a la persona natural o empresa que realiza reservas dentro de la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_cliente | INTEGER | Clave primaria | Identificador único del cliente |
| nombre | VARCHAR(100) | Simple | Nombre de la persona natural o razón social de la empresa |
| tipo_cliente | VARCHAR(20) | Simple | Indica si el cliente es una persona natural o una empresa |
| telefono | VARCHAR(20) | Multivaluado | Uno o varios números de contacto asociados al cliente |

(Se consideró modelar a las personas naturales y empresas como entidades separadas, pero se decidió usar una única entidad CLIENTE con el atributo tipo_cliente, ya que ambas cumplen la misma función dentro del sistema: realizar reservas. Esta opción reduce duplicidad y simplifica el modelo). 

## SEDE

Representa cada ubicación física perteneciente a la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_sede | INTEGER | Clave primaria | Identificador único de la sede |
| nombre | VARCHAR(100) | Simple | Nombre de la sede |
| direccion | VARCHAR(150) | Simple | Dirección física de la sede |
| ciudad | VARCHAR(80) | Simple | Ciudad donde se encuentra la sede |

## ESPACIO

Representa cada sala o escritorio disponible para reserva dentro de una sede de la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_espacio | INTEGER | Clave primaria | Identificador único del espacio |
| nombre | VARCHAR(100) | Simple | Nombre o código utilizado para identificar el espacio |
| tipo_espacio | VARCHAR(30) | Simple | Indica si el espacio corresponde a una sala o a un escritorio |
| tarifa | DECIMAL(12,2) | Simple | Valor asociado al uso del espacio, determinado según la sede |

## RESERVA

Representa una reserva realizada por un cliente sobre uno o varios espacios de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_reserva | INTEGER | Clave primaria | Identificador único de la reserva |
| fecha_inicio | DATE | Simple | Fecha en la que comienza la reserva |
| fecha_fin | DATE | Simple | Fecha en la que termina la reserva |
| hora_inicio | TIME | Simple | Hora de inicio cuando la reserva se realiza por horas |
| hora_fin | TIME | Simple | Hora de finalización cuando la reserva se realiza por horas |
| modalidad | VARCHAR(20) | Simple | Indica si la reserva se realiza por hora o por día |
| duracion | — | Derivado | Se obtiene a partir de las fechas y/o horas de inicio y fin |

## CUOTA

Representa cada pago parcial asociado a una reserva. Una reserva puede ser pagada mediante una o varias cuotas.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| numero_cuota | INTEGER | Clave parcial | Número consecutivo que identifica la cuota dentro de una reserva |
| monto_pagado | DECIMAL(12,2) | Simple | Valor pagado en la cuota |
| fecha_pago | DATE | Simple | Fecha en la que se realizó el pago |

## RESERVA_ESPACIO

Representa la asociación entre una reserva y cada uno de los espacios incluidos en ella. Permite que una misma reserva contenga varios espacios y que un espacio pueda formar parte de diferentes reservas a lo largo del tiempo.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_reserva | INTEGER | Clave compuesta / referencia a RESERVA | Identifica la reserva a la que pertenece la asignación |
| id_espacio | INTEGER | Clave compuesta / referencia a ESPACIO | Identifica el espacio incluido en la reserva |


