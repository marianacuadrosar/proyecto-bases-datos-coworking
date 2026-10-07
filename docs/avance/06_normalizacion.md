# Normalización hasta 3FN

Este documento muestra cómo se llega a las tablas del modelo relacional (`05_modelo_relacional.md`) aplicando normalización paso a paso.

La idea es comprobar el modelo por un segundo camino.

Persona 3 llegó a las tablas desde el diagrama E/R. Aquí se llega desde el otro lado: se parte de una sola planilla con todos los datos mezclados y se va partiendo hasta que no quede información repetida.

Si los dos caminos terminan en las mismas tablas, el modelo está bien hecho.

**Convenciones**

- `A → B` se lee "A determina a B": si dos filas tienen el mismo valor de A, tienen el mismo valor de B.
- **DF** = dependencia funcional, **DP** = dependencia parcial, **DT** = dependencia transitiva.
- Las llaves primarias van <ins>subrayadas</ins> y las llaves foráneas en *cursiva*, igual que en `05_modelo_relacional.md`.
- `{ }` marca un grupo que se repite y `( )` un atributo compuesto.

---

## 0. Las tres reglas

| Forma normal | Qué exige | Qué problema elimina |
|---|---|---|
| **1FN** | Cada celda guarda un solo valor. No hay grupos repetidos. Toda tabla tiene llave primaria | Listas dentro de una celda y columnas tipo `espacio1`, `espacio2`, `espacio3` |
| **2FN** | Estar en 1FN y que ningún atributo dependa de **solo una parte** de una llave compuesta | Dependencias parciales |
| **3FN** | Estar en 2FN y que ningún atributo no clave dependa de **otro atributo no clave** | Dependencias transitivas: `llave → X → Y`, donde X no es llave |

---

## 1. Esquema inicial sin normalizar

### 1.1 De dónde sale

Antes de tener base de datos, la recepción de una sede anotaría cada reserva en un formato como este.

Es el formato de la reserva 10 del ejemplo que usa Persona 3: una empresa reserva una sala de juntas y dos escritorios, y paga en dos cuotas.

```
RESERVA N.° 10                         Creada: 2026-03-02     Estado: CONFIRMADA
Modalidad: (2) Día                                         Valor total: $590.000
--------------------------------------------------------------------------------
CLIENTE N.° 15 · EMPRESA · registrado el 2026-02-10
Razón social: Andina Analytics S.A.S.             NIT: 901234567-8
Contacto: Laura Gómez                             Email: reservas@andinaanalytics.co
Teléfonos: 3104567890 · 6017654321
--------------------------------------------------------------------------------
ESPACIOS
[3] CH-SJ-01 · capacidad 10 · tipo (1) Sala de juntas
    Sede (1) Chapinero · Calle 63 # 9-45, Chapinero Alto, Bogotá · 07:00 a 21:00
    2026-03-05 08:00 → 2026-03-05 18:00 · tarifa de lista $500.000 · cobrada $450.000
[7] CH-ES-04 · capacidad 1 · tipo (2) Escritorio flexible
    Sede (1) Chapinero · Calle 63 # 9-45, Chapinero Alto, Bogotá · 07:00 a 21:00
    2026-03-05 08:00 → 2026-03-05 18:00 · tarifa de lista $70.000 · cobrada $70.000
[8] CH-ES-05 · capacidad 1 · tipo (2) Escritorio flexible
    Sede (1) Chapinero · Calle 63 # 9-45, Chapinero Alto, Bogotá · 07:00 a 21:00
    2026-03-05 08:00 → 2026-03-05 18:00 · tarifa de lista $70.000 · cobrada $70.000
--------------------------------------------------------------------------------
PAGOS
Cuota 1 · 2026-03-02 · $200.000 · Tarjeta de crédito
Cuota 2 · 2026-03-04 · $150.000 · Transferencia
```

La sala de juntas se cobró a $450.000 y no a los $500.000 de lista porque Andina Analytics tiene un convenio empresarial del 10 %.

Este detalle importa más adelante (sección 5.3).

### 1.2 El esquema

Si todo el formato se guarda como una sola tabla, el esquema queda así:

```
RESERVA_SN (
    reserva_id, fecha_creacion, estado, modalidad_id, modalidad_nombre, valor_total,
    cliente_id, tipo_cliente, email, fecha_registro, { telefono },
    documento, nombres, apellidos, fecha_nacimiento,
    nit, razon_social, nombre_contacto,
    { espacio_id, codigo, capacidad,
      tipo_id, tipo_nombre, tipo_descripcion,
      sede_id, sede_nombre, direccion(calle, numero, barrio, ciudad), hora_apertura, hora_cierre,
      inicio, fin, tarifa_aplicada, valor_lista },
    { num_cuota, monto, fecha_pago, metodo_pago }
)
```

Tiene todos los atributos del diagrama E/R (Figura 1).

Algunos nombres llevan prefijo (`sede_nombre`, `tipo_nombre`, `modalidad_nombre`) porque en una sola tabla no puede haber tres columnas llamadas `nombre`.

`valor_lista` es el precio publicado para esa sede, ese tipo de espacio y esa modalidad. En el diagrama E/R es el atributo `valor` de TARIFA.

`tarifa_aplicada` es lo que de verdad se le cobró al cliente en esa reserva.

Tiene tres problemas a la vista:

| Problema | Dónde |
|---|---|
| Atributo compuesto | `direccion` guarda calle, número, barrio y ciudad en un solo dato |
| Atributo multivaluado | `{ telefono }`: el cliente 15 tiene dos teléfonos |
| Grupos repetidos | `{ espacios }`: la reserva 10 tiene tres. `{ cuotas }`: la reserva 10 tiene dos |

Además tiene un atributo derivado, `valor_total`, que se puede calcular con otros datos.

### 1.3 Los datos de ejemplo

Estas son las cuatro reservas que se usan en todo el documento, vistas como la planilla sin normalizar.

Cada fila es una reserva. Las celdas con varias líneas tienen varios valores.

| reserva_id | fecha_creacion | modalidad | cliente_id | cliente | telefono | espacio_id | sede | tipo | tarifa_aplicada | num_cuota | monto |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 10 | 2026-03-02 | Día | 15 | Andina Analytics S.A.S. | 3104567890<br>6017654321 | 3<br>7<br>8 | Chapinero<br>Chapinero<br>Chapinero | Sala de juntas<br>Escritorio flexible<br>Escritorio flexible | 450000<br>70000<br>70000 | 1<br>2 | 200000<br>150000 |
| 11 | 2026-05-10 | Hora | 22 | Santiago Rojas Pardo | 3157782190 | 12 | Usaquén | Sala de juntas | 95000 | 1 | 80000 |
| 12 | 2026-09-15 | Hora | 15 | Andina Analytics S.A.S. | 3104567890<br>6017654321 | 3 | Chapinero | Sala de juntas | 80000 | 1 | 240000 |
| 13 | 2026-09-22 | Día | 22 | Santiago Rojas Pardo | 3157782190 | 3 | Chapinero | Sala de juntas | 500000 | 1<br>2 | 250000<br>250000 |

*(Por espacio no caben todas las columnas. Las que faltan siguen el mismo patrón.)*

Datos de las dos sedes:

| sede_id | sede_nombre | calle | numero | barrio | ciudad | hora_apertura | hora_cierre |
|---|---|---|---|---|---|---|---|
| 1 | Chapinero | Calle 63 | 9-45 | Chapinero Alto | Bogotá | 07:00 | 21:00 |
| 2 | Usaquén | Carrera 7 | 119-14 | Usaquén | Bogotá | 06:00 | 22:00 |

### 1.4 Por qué esta tabla da problemas

Con solo cuatro reservas ya aparecen las tres anomalías clásicas.

**Anomalía de inserción.** No se puede guardar algo que todavía no tiene reserva.

- Una sede nueva, por ejemplo Cedritos, no se puede registrar hasta que alguien reserve allá.
- Un cliente que se registra hoy no queda guardado hasta que haga su primera reserva.
- La tarifa de escritorio por hora en Usaquén no tiene dónde quedar si nadie lo ha reservado.

**Anomalía de actualización.** Un mismo dato está escrito en muchas filas.

- Si Chapinero pasa a cerrar a las 22:00, hay que cambiarlo en cinco lugares: los tres espacios de la reserva 10, el de la 12 y el de la 13.
- Si se olvida uno, la base dice que Chapinero cierra a dos horas distintas.
- Lo mismo pasa con el email del cliente 15, escrito en las reservas 10 y 12.

**Anomalía de eliminación.** Al borrar una reserva se pierde información que no era de la reserva.

- La reserva 11 es la única donde aparece Usaquén.
- Si se borra, desaparecen la sede de Usaquén, el espacio 12 y la tarifa de sala de juntas por hora en esa sede.

---

## 2. Dependencias funcionales del caso

Antes de normalizar hay que saber qué determina a qué.

Cada dependencia sale de una regla del negocio, no de los datos de ejemplo. Los datos solo sirven para ilustrarla.

| # | Dependencia funcional | Regla del negocio que la justifica |
|---|---|---|
| DF1 | `reserva_id → fecha_creacion, estado, modalidad_id, cliente_id` | Una reserva se crea una vez, tiene un estado, se cobra con una sola modalidad (relación `aplica`, 1:N) y la hace un solo cliente (relación `realiza`, 1:N) |
| DF2 | `modalidad_id → modalidad_nombre` | Cada modalidad tiene un nombre: 1 = Hora, 2 = Día |
| DF3 | `cliente_id → tipo_cliente, email, fecha_registro, documento, nombres, apellidos, fecha_nacimiento, nit, razon_social, nombre_contacto` | Cada cliente tiene un solo registro con sus datos (supuesto 2) |
| DF4 | `espacio_id → codigo, capacidad, sede_id, tipo_id` | Cada espacio pertenece a una sola sede (supuesto 3) y tiene un solo tipo (relación `clasifica`, 1:N) |
| DF5 | `sede_id → sede_nombre, calle, numero, barrio, ciudad, hora_apertura, hora_cierre` | Cada sede está en un solo lugar y tiene un solo horario (supuesto 1) |
| DF6 | `tipo_id → tipo_nombre, tipo_descripcion` | Cada tipo de espacio tiene un nombre y una descripción |
| DF7 | `(sede_id, tipo_id, modalidad_id) → valor_lista` | El precio de lista depende de la sede, el tipo y la modalidad juntos (decisión de diseño 2 y relación ternaria TARIFA) |
| DF8 | `(reserva_id, espacio_id) → inicio, fin, tarifa_aplicada` | Cada espacio de una reserva tiene su propio horario y su propio precio cobrado |
| DF9 | `(reserva_id, num_cuota) → monto, fecha_pago, metodo_pago` | Cada cuota se identifica con su reserva y su número (supuestos 9 y 10) |

El teléfono no aparece en la tabla porque **no es una dependencia funcional**.

`cliente_id` no determina **un** teléfono: el cliente 15 tiene dos. Es un atributo multivaluado y se resuelve en la 1FN.

### 2.1 Dependencias que se revisaron y no se cumplen

Para no inventar dependencias, también se revisaron las que parecían posibles. Ninguna se cumple:

| ¿Se cumple…? | No, porque… | Consecuencia |
|---|---|---|
| `tipo_id → capacidad` | Dos salas de juntas pueden tener distinta capacidad: el espacio 3 es para 10 personas y el 12 para 8 | `capacidad` se queda en ESPACIO |
| `reserva_id → inicio, fin` | Dentro de una misma reserva la sala puede ser de 9 a 11 y los escritorios de 9 a 6 | `inicio` y `fin` van en RESERVA_ESPACIO, no en RESERVA |
| `(sede_id, tipo_id, modalidad_id) → tarifa_aplicada` | El espacio 3 (Chapinero, sala de juntas, día) se cobró $450.000 en la reserva 10 y $500.000 en la 13 | `tarifa_aplicada` no se va a TARIFA (sección 5.3) |
| `cliente_id → modalidad_id` | El cliente 15 reservó por día (reserva 10) y por hora (reserva 12) | La modalidad es de la reserva, no del cliente |
| `barrio → ciudad` | Hay barrios con el mismo nombre en distintas ciudades, por ejemplo "El Prado" en Bogotá y en Barranquilla | `barrio` y `ciudad` quedan juntos en SEDE sin separar |

### 2.2 Llaves candidatas

Algunos atributos también identifican una fila por sí solos. Se llaman **llaves candidatas**.

| Tabla | Llave candidata | Por qué |
|---|---|---|
| Espacio | `(sede_id, codigo)` | Dos espacios de la misma sede no tienen el mismo código |
| Persona natural | `documento` | Dos personas no tienen el mismo número de documento |
| Empresa | `nit` | Dos empresas no tienen el mismo NIT |

Una dependencia como `documento → nombres` **no** viola la 3FN, porque `documento` es llave candidata.

La 3FN solo prohíbe que un atributo dependa de otro que **no** es llave.
