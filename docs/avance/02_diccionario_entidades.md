# Diccionario de entidades y atributos

Los nombres de este diccionario son los mismos del diagrama E/R (`04_diagrama_er_chen.md`), del modelo relacional (`05_modelo_relacional.md`) y del script `sql/01_ddl.sql`. Todos los identificadores siguen el formato `entidad_id` en snake_case.

Las llaves foráneas no son atributos del modelo E/R: salen de las relaciones al pasar a tablas. Se incluyen aquí, marcadas como llave foránea, para que el diccionario coincida columna por columna con el SQL.

## SEDE

Representa cada ubicación física perteneciente a la red de coworking.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| sede_id | INT | Clave primaria | Identificador único de la sede |
| nombre | VARCHAR(100) | Simple | Nombre de la sede |
| direccion | — | Compuesto | Dirección física de la sede. Se guarda en sus cuatro componentes |
| ↳ calle | VARCHAR(150) | Componente simple | Calle o carrera principal de la sede |
| ↳ numero | VARCHAR(10) | Componente simple | Número de la placa, por ejemplo 9-45 |
| ↳ barrio | VARCHAR(80) | Componente simple | Barrio donde se encuentra la sede |
| ↳ ciudad | VARCHAR(80) | Componente simple | Ciudad donde se encuentra la sede |
| hora_apertura | TIME | Simple | Hora a la que abre la sede |
| hora_cierre | TIME | Simple | Hora a la que cierra la sede |

## TIPO_ESPACIO

Representa la categoría a la que pertenece un espacio, por ejemplo sala de reuniones o escritorio flexible.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| tipo_id | INT | Clave primaria | Identificador único del tipo de espacio |
| nombre | VARCHAR(50) | Simple (único) | Nombre de la categoría del espacio |
| descripcion | VARCHAR(150) | Simple | Descripción general del tipo de espacio |

## MODALIDAD

Representa la modalidad de cobro de una reserva: por horas o por día.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| modalidad_id | INT | Clave primaria | Identificador único de la modalidad |
| nombre | VARCHAR(20) | Simple (único) | Nombre de la modalidad: Hora o Dia |

## CLIENTE

Representa a quien realiza reservas en la red de coworking. Es la entidad general (superclase) de la especialización en PERSONA_NATURAL y EMPRESA: guarda los datos que tienen todos los clientes, y cada subclase guarda los suyos (decisión de diseño 1).

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| cliente_id | INT | Clave primaria | Identificador único del cliente |
| email | VARCHAR(100) | Simple | Correo electrónico de contacto del cliente |
| fecha_registro | DATE | Simple | Fecha en la que el cliente se registró en la red |
| tipo_cliente | VARCHAR(20) | Simple | Indica en qué subclase está el cliente: NATURAL o EMPRESA |
| telefono | VARCHAR(20) | Multivaluado | Uno o varios números de contacto del cliente. Se guarda en la tabla TELEFONO_CLIENTE |

## PERSONA_NATURAL

Subclase de CLIENTE. Guarda los datos propios de los clientes que son personas naturales.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| cliente_id | INT | Clave primaria y llave foránea a CLIENTE | El mismo identificador del cliente, heredado de CLIENTE |
| documento | VARCHAR(20) | Simple (único) | Número de documento de identidad |
| nombres | VARCHAR(60) | Simple | Nombres de la persona |
| apellidos | VARCHAR(60) | Simple | Apellidos de la persona |
| fecha_nacimiento | DATE | Simple | Fecha de nacimiento de la persona |

## EMPRESA

Subclase de CLIENTE. Guarda los datos propios de los clientes que son empresas.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| cliente_id | INT | Clave primaria y llave foránea a CLIENTE | El mismo identificador del cliente, heredado de CLIENTE |
| nit | VARCHAR(15) | Simple (único) | Número de identificación tributaria, con dígito de verificación |
| razon_social | VARCHAR(120) | Simple | Nombre legal de la empresa |
| nombre_contacto | VARCHAR(100) | Simple | Persona de la empresa encargada de las reservas |

## ESPACIO

Representa cada sala, oficina o escritorio que se puede reservar dentro de una sede.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| espacio_id | INT | Clave primaria | Identificador único del espacio |
| codigo | VARCHAR(100) | Simple | Código del espacio dentro de su sede, por ejemplo SR-01. No se repite en la misma sede |
| capacidad | INT | Simple | Número máximo de personas que caben en el espacio |
| sede_id | INT | Llave foránea a SEDE | Sede a la que pertenece (relación `tiene`) |
| tipo_id | INT | Llave foránea a TIPO_ESPACIO | Tipo del espacio (relación `clasifica`) |

## TARIFA (relación ternaria)

Representa el precio vigente de un tipo de espacio en una sede para una modalidad. Es la relación ternaria entre SEDE, TIPO_ESPACIO y MODALIDAD (decisión de diseño 2): el precio depende de las tres a la vez.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| sede_id | INT | Clave compuesta y llave foránea a SEDE | Sede a la que aplica la tarifa |
| tipo_id | INT | Clave compuesta y llave foránea a TIPO_ESPACIO | Tipo de espacio al que aplica la tarifa |
| modalidad_id | INT | Clave compuesta y llave foránea a MODALIDAD | Modalidad a la que aplica la tarifa |
| valor | DECIMAL(12,2) | Simple | Precio vigente para esa combinación de sede, tipo y modalidad |

## RESERVA

Representa una reserva hecha por un cliente sobre uno o varios espacios de una misma sede.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| reserva_id | INT | Clave primaria | Identificador único de la reserva |
| fecha_creacion | DATE | Simple | Fecha en la que se registró la reserva |
| estado | VARCHAR(20) | Simple | PENDIENTE, CONFIRMADA, CANCELADA o FINALIZADA. Una reserva nueva empieza PENDIENTE |
| valor_total | — | Derivado | No se guarda. Se calcula sumando, por cada espacio de la reserva, `tarifa_aplicada` × horas (modalidad Hora) o × 1 (modalidad Dia). Lo calcula la función `fn_valor_reserva` |
| cliente_id | INT | Llave foránea a CLIENTE | Cliente que hizo la reserva (relación `realiza`) |
| modalidad_id | INT | Llave foránea a MODALIDAD | Modalidad con la que se cobra (relación `aplica`) |

El horario no está en RESERVA sino en RESERVA_ESPACIO, porque cada espacio de una misma reserva puede usarse en un horario distinto (supuesto 18).

## RESERVA_ESPACIO (entidad asociativa)

Resuelve la relación N:M entre RESERVA y ESPACIO: una reserva puede incluir varios espacios y un espacio puede estar en muchas reservas a lo largo del tiempo.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| reserva_id | INT | Clave compuesta y llave foránea a RESERVA | Reserva a la que pertenece la línea |
| espacio_id | INT | Clave compuesta y llave foránea a ESPACIO | Espacio incluido en la reserva |
| inicio | DATETIME | Simple | Fecha y hora en que empieza el uso de ese espacio |
| fin | DATETIME | Simple | Fecha y hora en que termina el uso de ese espacio |
| tarifa_aplicada | DECIMAL(12,2) | Simple | Precio que se cobró por ese espacio en esa reserva. Puede ser distinto de la tarifa vigente (supuesto 19) |

## CUOTA (entidad débil)

Representa cada pago parcial de una reserva. Depende de RESERVA: "cuota 2" no identifica nada sin su reserva.

| Atributo | Tipo de dato | Clasificación | Descripción |
|---|---|---|---|
| reserva_id | INT | Clave compuesta y llave foránea a RESERVA | Reserva dueña de la cuota (relación identificadora `se paga en`) |
| num_cuota | INT | Clave parcial | Número consecutivo de la cuota dentro de su reserva |
| monto | DECIMAL(12,2) | Simple | Valor de la cuota |
| fecha_pago | DATE | Simple | Fecha en la que se pagó. Vacía mientras la cuota está pendiente |
| metodo_pago | VARCHAR(30) | Simple | Medio de pago: Efectivo, Tarjeta de crédito, Tarjeta débito, Transferencia, PSE o Nequi |

## Resumen de elementos exigidos

| Elemento | Dónde está |
|---|---|
| Atributo compuesto | `direccion` de SEDE: calle, numero, barrio y ciudad |
| Atributo multivaluado | `telefono` de CLIENTE |
| Atributo derivado | `valor_total` de RESERVA |
| Entidad débil | CUOTA, con clave parcial `num_cuota` |
| Entidad asociativa | RESERVA_ESPACIO, con atributos propios `inicio`, `fin` y `tarifa_aplicada` |
| Relación ternaria | TARIFA, entre SEDE, TIPO_ESPACIO y MODALIDAD |
| Especialización | CLIENTE se divide en PERSONA_NATURAL y EMPRESA (disjunta y total) |
