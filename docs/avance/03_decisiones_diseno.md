# Decisiones de diseño

## 1. CLIENTE como superclase de PERSONA_NATURAL y EMPRESA

Los clientes pueden ser personas naturales o empresas. Las dos hacen lo mismo dentro del sistema, reservar espacios, pero no guardan los mismos datos: una persona tiene documento, nombres, apellidos y fecha de nacimiento, y una empresa tiene NIT, razón social y persona de contacto.

Se consideraron tres formas de modelarlo:

| Alternativa | Problema |
|---|---|
| Una sola entidad CLIENTE con todos los atributos y un campo `tipo_cliente` | Cada cliente dejaría vacía casi la mitad de sus columnas: una empresa no tiene fecha de nacimiento y una persona no tiene NIT |
| Dos entidades independientes, PERSONA_NATURAL y EMPRESA, sin entidad común | RESERVA tendría que relacionarse con dos entidades distintas, y una llave foránea solo puede apuntar a una tabla. Lo mismo pasaría con los teléfonos |
| **CLIENTE como entidad general, especializada en PERSONA_NATURAL y EMPRESA** (la elegida) | — |

Se eligió la especialización. CLIENTE guarda lo que comparten todos los clientes: email, fecha de registro, teléfonos y `tipo_cliente`. PERSONA_NATURAL y EMPRESA guardan solo lo propio de cada tipo y usan el mismo `cliente_id` de CLIENTE como llave.

La especialización es disjunta y total (supuesto 15): cada cliente es exactamente una persona natural o una empresa. `tipo_cliente` dice en cuál de las dos subclases están sus datos.

Así RESERVA y TELEFONO_CLIENTE se relacionan con una sola entidad, CLIENTE, sin importar el tipo de cliente, y ninguna tabla queda con columnas vacías. Ver `04_diagrama_er_chen.md` y `05_modelo_relacional.md`, sección 3.6.

## 2. Modelar la tarifa mediante una relación ternaria

Inicialmente se consideró guardar la tarifa como un atributo de ESPACIO. Esa opción repetiría el mismo precio en todos los espacios iguales de una sede y no permitiría tener un precio por hora y otro por día.

Se decidió modelar la tarifa como una relación ternaria, TARIFA, entre SEDE, TIPO_ESPACIO y MODALIDAD, con el atributo `valor`. El precio depende de la combinación de los tres.

Por ejemplo, una sala de reuniones tiene un precio por hora y otro por día, y los dos cambian de una sede a otra.

Así las tarifas se mantienen aparte de los espacios individuales y cada precio se escribe una sola vez. La normalización llega a la misma tabla por su cuenta (`06_normalizacion.md`, dependencia DT5).

Es un supuesto del grupo (supuesto 8): el caso dice que la tarifa depende de la sede y que hay reservas por hora o por día, pero no dice cómo se combinan esas variables para fijar el precio.
