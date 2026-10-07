# Decisiones de diseño

## 1. Modelar persona natural y empresa dentro de una sola entidad CLIENTE

Durante el diseño se consideraron dos alternativas para representar los tipos de clientes de la red de coworking.

La primera alternativa consistía en crear entidades separadas para PERSONA_NATURAL y EMPRESA. La segunda consistía en utilizar una única entidad CLIENTE con un atributo llamado tipo_cliente que permitiera distinguir entre ambos tipos.

Se decidió utilizar una sola entidad CLIENTE porque tanto las personas naturales como las empresas cumplen la misma función principal dentro del sistema: realizar reservas de espacios. Separarlas en dos entidades introduciría una mayor complejidad en el modelo sin que el caso de negocio especifique atributos suficientemente diferentes para justificar dicha separación.

Por esta razón, CLIENTE incluye el atributo tipo_cliente, que permite identificar si el cliente corresponde a una persona natural o una empresa.

**Actualización tras el diagrama E/R.** Al detallar los atributos se vio que sí hay datos distintos para cada tipo: una persona natural tiene documento, nombres, apellidos y fecha de nacimiento, y una empresa tiene NIT, razón social y persona de contacto. Con una sola tabla, cada cliente dejaría vacía casi la mitad de sus columnas.

Por eso la decisión final combina las dos alternativas:

- Se conserva una única entidad CLIENTE para lo común (email, fecha de registro, teléfonos y tipo_cliente). Así RESERVA sigue apuntando a una sola entidad, que era el motivo original de esta decisión.
- CLIENTE se especializa en PERSONA_NATURAL y EMPRESA (disjunta y total, supuesto 15) para guardar los datos propios de cada tipo.

`tipo_cliente` indica en cuál de las dos subclases están los datos del cliente. Ver `04_diagrama_er_chen.md` y `05_modelo_relacional.md`, sección 3.6.

## 2. Modelar la tarifa mediante una relación ternaria

Inicialmente se consideró almacenar la tarifa como un atributo directo de la entidad ESPACIO. Sin embargo, esta alternativa limitaría la posibilidad de representar precios diferentes según la sede, el tipo de espacio y la modalidad de reserva.

Se decidió modelar la tarifa mediante una relación ternaria entre SEDE, TIPO_ESPACIO y MODALIDAD_RESERVA. De esta manera, el valor de la tarifa depende de la combinación de los tres elementos.

Por ejemplo, una sala de juntas puede tener una tarifa diferente según la sede en la que se encuentre y dependiendo de si se reserva por hora o por día.

La relación DEFINE_TARIFA tendrá el atributo valor_tarifa, permitiendo mantener las tarifas de manera independiente de los espacios individuales y evitando duplicar información.

(Esta decisión se adopta como un supuesto adicional del grupo, ya que el caso establece que la tarifa depende de la sede y que existen reservas por hora o por día, pero no especifica de manera explícita cómo se combinan estas variables para determinar el precio). 
