# **Descripción del caso de negocio**
La Red de Espacios de Coworking administra diferentes sedes en las que ofrece salas y escritorios disponibles para reserva. Sus clientes pueden ser personas naturales o empresas y pueden realizar reservas por horas o por día, dependiendo de sus necesidades. Una misma reserva puede incluir varios espacios simultáneamente, como una sala de juntas y varios escritorios. Cada espacio pertenece a una sede y cuenta con una tarifa asociada que depende de dicha sede. El sistema debe permitir registrar la información de los clientes, las sedes, los espacios disponibles, las reservas realizadas y los pagos correspondientes. Cada reserva puede ser pagada mediante una o varias cuotas, por lo que también es necesario mantener información sobre los pagos realizados.

# **Supuestos del caso**
1. Cada sede tendrá un identificador único.
2. Cada cliente tendrá un identificador único.
3. Cada espacio tendrá un identificador único y pertenecerá a una sola sede.
4. Un cliente puede realizar múltiples reservas a lo largo del tiempo.
5. Una reserva puede incluir uno o varios espacios.
6. Un mismo espacio puede aparecer en distintas reservas, siempre que no exista cruce de horario.
7. Las reservas pueden realizarse por hora o por día.
8. La tarifa de un espacio depende de la sede y del tipo de espacio.
9. Cada cuota pertenece a una única reserva.
10. El número de cuota es consecutivo dentro de cada reserva.
11. La cuota se modelará como entidad débil.
12. La relación entre RESERVA y ESPACIO se representará mediante una entidad asociativa.
13. Se utilizarán identificadores internos para las entidades principales porque el caso no proporciona llaves naturales suficientes.
