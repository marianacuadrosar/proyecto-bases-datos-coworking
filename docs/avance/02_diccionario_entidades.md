## CLIENTE

Representa a la persona natural o empresa que realiza reservas dentro de la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_cliente | INTEGER | Clave primaria | Identificador único del cliente |
| nombre | VARCHAR(100) | Simple | Nombre de la persona natural o razón social de la empresa |
| tipo_cliente | VARCHAR(20) | Simple | Indica si el cliente es una persona natural o una empresa |
| telefono | VARCHAR(20) | Multivaluado | Uno o varios números de contacto asociados al cliente |
| email | VARCHAR(100) | Simple | Correo electrónico de contacto del cliente |
| fecha_registro | DATE | Simple | Fecha en la que el cliente se registró en la red de coworking |

(Se consideró modelar a las personas naturales y empresas como entidades separadas, pero se decidió usar una única entidad CLIENTE con el atributo tipo_cliente, ya que ambas cumplen la misma función dentro del sistema: realizar reservas. Esta opción reduce duplicidad y simplifica el modelo). 

(Actualización: al construir el diagrama E/R se vio que personas y empresas sí guardan datos distintos, como documento y fecha de nacimiento frente a NIT y razón social. Por eso CLIENTE se mantiene como la entidad general que realiza las reservas, y se especializa en PERSONA_NATURAL y EMPRESA. El atributo `nombre` se concreta como `nombres` y `apellidos` en PERSONA_NATURAL, y como `razon_social` en EMPRESA. Ver la decisión de diseño 1 y el supuesto 15.)

## PERSONA_NATURAL

Subclase de CLIENTE. Guarda los datos propios de los clientes que son personas naturales.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_cliente | INTEGER | Clave primaria / referencia a CLIENTE | Mismo identificador del cliente, heredado de CLIENTE |
| documento | VARCHAR(20) | Simple (único) | Número de documento de identidad |
| nombres | VARCHAR(60) | Simple | Nombres de la persona |
| apellidos | VARCHAR(60) | Simple | Apellidos de la persona |
| fecha_nacimiento | DATE | Simple | Fecha de nacimiento de la persona |

## EMPRESA

Subclase de CLIENTE. Guarda los datos propios de los clientes que son empresas.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_cliente | INTEGER | Clave primaria / referencia a CLIENTE | Mismo identificador del cliente, heredado de CLIENTE |
| nit | VARCHAR(15) | Simple (único) | Número de identificación tributaria de la empresa |
| razon_social | VARCHAR(120) | Simple | Nombre legal de la empresa |
| nombre_contacto | VARCHAR(100) | Simple | Persona de la empresa encargada de las reservas |

## SEDE

Representa cada ubicación física perteneciente a la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_sede | INTEGER | Clave primaria | Identificador único de la sede |
| nombre | VARCHAR(100) | Simple | Nombre de la sede |
| direccion | — | Compuesto | Dirección física de la sede |
| ↳ calle | VARCHAR(150) | Componente simple | Calle o dirección principal de la sede |
| ↳ numero | VARCHAR(10) | Componente simple | Número de la placa, por ejemplo 9-45 |
| ↳ barrio | VARCHAR(80) | Componente simple | Barrio donde se encuentra la sede |
| ↳ ciudad | VARCHAR(80) | Componente simple | Ciudad donde se encuentra la sede |
| hora_apertura | TIME | Simple | Hora a la que abre la sede |
| hora_cierre | TIME | Simple | Hora a la que cierra la sede |

## ESPACIO

Representa cada sala o escritorio disponible para reserva dentro de una sede de la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_espacio | INTEGER | Clave primaria | Identificador único del espacio |
| nombre | VARCHAR(100) | Simple | Nombre o código utilizado para identificar el espacio |
| capacidad | INTEGER | Simple | Número máximo de personas que caben en el espacio |

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
| fecha_creacion | DATE | Simple | Fecha en la que se registró la reserva |
| estado | VARCHAR(20) | Simple | Estado de la reserva, por ejemplo PENDIENTE, CONFIRMADA o CANCELADA |
| valor_total | — | Derivado | Se calcula sumando, para cada espacio de la reserva, `tarifa_aplicada` × número de horas o de días (según la modalidad). No se almacena |

(Nota: en el diagrama E/R el horario se registra por cada espacio de la reserva, con `inicio` y `fin` en RESERVA_ESPACIO (supuesto 18), y la modalidad se representa con la entidad MODALIDAD_RESERVA. La duración de cada espacio se calcula con esos dos datos.)

## CUOTA

Representa cada pago parcial asociado a una reserva. Una reserva puede ser pagada mediante una o varias cuotas.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| numero_cuota | INTEGER | Clave parcial | Número consecutivo que identifica la cuota dentro de una reserva |
| monto_pagado | DECIMAL(12,2) | Simple | Valor pagado en la cuota |
| fecha_pago | DATE | Simple | Fecha en la que se realizó el pago |
| metodo_pago | VARCHAR(30) | Simple | Medio de pago de la cuota, por ejemplo tarjeta, transferencia o efectivo |

## RESERVA_ESPACIO

Representa la asociación entre una reserva y cada uno de los espacios incluidos en ella. Permite que una misma reserva contenga varios espacios y que un espacio pueda formar parte de diferentes reservas a lo largo del tiempo.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_reserva | INTEGER | Clave compuesta / referencia a RESERVA | Identifica la reserva a la que pertenece la asignación |
| id_espacio | INTEGER | Clave compuesta / referencia a ESPACIO | Identifica el espacio incluido en la reserva |
| inicio | DATETIME | Simple | Fecha y hora en que empieza el uso de ese espacio dentro de la reserva |
| fin | DATETIME | Simple | Fecha y hora en que termina el uso de ese espacio dentro de la reserva |
| tarifa_aplicada | DECIMAL(12,2) | Simple | Precio que se cobró por ese espacio en esa reserva (supuesto 19) |

## TIPO_ESPACIO

Representa la categoría a la que pertenece un espacio disponible dentro de la red de coworking, por ejemplo, sala de juntas o escritorio individual.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_tipo_espacio | INTEGER | Clave primaria | Identificador único del tipo de espacio |
| nombre_tipo | VARCHAR(50) | Simple | Nombre de la categoría del espacio |
| descripcion | VARCHAR(150) | Simple | Descripción general del tipo de espacio |

## MODALIDAD_RESERVA

Representa la modalidad de cobro utilizada para una reserva, según si el espacio se reserva por horas o por día.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_modalidad | INTEGER | Clave primaria | Identificador único de la modalidad |
| nombre_modalidad | VARCHAR(20) | Simple | Nombre de la modalidad, por ejemplo Hora o Día |

## TARIFA (relación ternaria)

Representa el precio vigente de un tipo de espacio en una sede para una modalidad. Es una relación ternaria entre SEDE, TIPO_ESPACIO y MODALIDAD_RESERVA (decisión de diseño 2): el precio depende de las tres a la vez.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| id_sede | INTEGER | Clave compuesta / referencia a SEDE | Sede a la que aplica la tarifa |
| id_tipo_espacio | INTEGER | Clave compuesta / referencia a TIPO_ESPACIO | Tipo de espacio al que aplica la tarifa |
| id_modalidad | INTEGER | Clave compuesta / referencia a MODALIDAD_RESERVA | Modalidad (hora o día) a la que aplica la tarifa |
| valor_tarifa | DECIMAL(12,2) | Simple | Precio vigente para esa combinación de sede, tipo y modalidad |

## Resumen de elementos exigidos

| Elemento | Dónde está |
|---|---|
| Atributo compuesto | `direccion` de SEDE: calle, numero, barrio y ciudad |
| Atributo multivaluado | `telefono` de CLIENTE |
| Atributos derivados | `valor_total` y `duracion` de RESERVA |
| Entidad débil | CUOTA, con clave parcial `numero_cuota` |
| Entidad asociativa | RESERVA_ESPACIO, con atributos propios `inicio`, `fin` y `tarifa_aplicada` |
| Relación ternaria | TARIFA, entre SEDE, TIPO_ESPACIO y MODALIDAD_RESERVA |
| Especialización | CLIENTE se divide en PERSONA_NATURAL y EMPRESA |

## Equivalencia de nombres con el diagrama E/R y el modelo relacional

Los nombres de este diccionario se escribieron antes del diagrama. En `04_diagrama_er_chen.md` y `05_modelo_relacional.md` algunos se escriben distinto, pero son el mismo atributo:

| En este diccionario | En el diagrama E/R y el modelo relacional |
|---|---|
| `id_cliente`, `id_sede`, `id_espacio`, `id_reserva` | `cliente_id`, `sede_id`, `espacio_id`, `reserva_id` |
| `id_tipo_espacio`, `id_modalidad` | `tipo_id`, `modalidad_id` |
| MODALIDAD_RESERVA, `nombre_modalidad` | MODALIDAD, `nombre` |
| `nombre_tipo` | `nombre` de TIPO_ESPACIO |
| ESPACIO.`nombre` | `codigo` |
| `numero_cuota`, `monto_pagado` | `num_cuota`, `monto` |
| `valor_tarifa` | `valor` de TARIFA |



