"""
Pruebas de las transacciones, funciones y validaciones de
sql/07_procedimientos_funciones.sql.

Datos de partida (sql/02_datos_prueba.sql), Sede Chapinero, 7:00 a 21:00:
    espacio 6   SR-01  sala de reuniones    68.500 por hora
    espacio 1   EF-01  escritorio flexible  12.000 por hora
    espacio 2   EF-02  escritorio flexible  12.000 por hora
    espacio 3   ED-01  escritorio dedicado  74.500 por día
    espacio 10  CB-01  cabina telefónica    sin tarifa por día
    espacio 24  EF-01  de la Sede Usaquén (otra sede)
    cliente 1   Andrés Patiño, documento 70719489
    cliente 2   Tequendama Ingeniería S.A.S.
    reserva 7   CANCELADA
    reserva 188 CONFIRMADA, con la cuota 1 pagada
    modalidad   1 = Hora, 2 = Dia

Las fechas son de marzo de 2027, donde no hay reservas.

Ejecutar desde la raíz del repositorio:
    pip install -r tests/requirements.txt
    pytest tests -v
"""

import json

import mysql.connector
import pytest

from conftest import contar, fila

HORA, DIA = 1, 2
TABLAS_RESERVA = ("reserva", "reserva_espacio", "cuota")
TABLAS_CLIENTE = ("cliente", "persona_natural", "empresa", "telefono_cliente")


# ------------------------------------------------------------
# Llamadas a los procedimientos, como las haría la aplicación
# ------------------------------------------------------------

def crear_reserva(db, cliente, modalidad, espacios, fecha,
                  inicio=None, fin=None, cuotas=1, metodo=None):
    cursor = db.cursor()
    resultado = cursor.callproc(
        "sp_crear_reserva",
        (cliente, modalidad, json.dumps(espacios), fecha, inicio, fin, cuotas, metodo, 0),
    )
    cursor.close()
    return resultado[8]                      # OUT p_reserva_id


def registrar_pago(db, reserva, metodo="Nequi"):
    cursor = db.cursor()
    resultado = cursor.callproc("sp_registrar_pago", (reserva, metodo, 0, 0))
    cursor.close()
    return resultado[2], resultado[3]        # OUT p_num_cuota, p_monto


def registrar_cliente(db, tipo, email, documento=None, nombres=None, apellidos=None,
                      nacimiento=None, nit=None, razon_social=None, contacto=None,
                      telefonos=("3001234567",)):
    cursor = db.cursor()
    resultado = cursor.callproc(
        "sp_registrar_cliente",
        (tipo, email, documento, nombres, apellidos, nacimiento,
         nit, razon_social, contacto, json.dumps(list(telefonos)), 0),
    )
    cursor.close()
    return resultado[10]                     # OUT p_cliente_id


def estado(db, reserva):
    return fila(db, "SELECT estado FROM reserva WHERE reserva_id = %s", (reserva,))[0]


# ------------------------------------------------------------
# T2 sp_crear_reserva
# ------------------------------------------------------------

def test_reserva_valida_hace_commit_en_las_tres_tablas(db):
    antes = contar(db, *TABLAS_RESERVA)

    reserva = crear_reserva(db, 2, HORA, [6, 1, 2], "2027-03-01",
                            "09:00", "12:00", cuotas=2, metodo="Transferencia")

    despues = contar(db, *TABLAS_RESERVA)
    assert despues["reserva"] == antes["reserva"] + 1
    assert despues["reserva_espacio"] == antes["reserva_espacio"] + 3
    assert despues["cuota"] == antes["cuota"] + 2

    # 3 h x (68.500 + 12.000 + 12.000) = 277.500; la cuota 1 ya está pagada
    valor, saldo = fila(db, "SELECT fn_valor_reserva(%s), fn_saldo_pendiente(%s)",
                        (reserva, reserva))
    assert valor == 277500
    assert saldo == 138750
    assert estado(db, reserva) == "CONFIRMADA"


def test_cruce_de_horario_hace_rollback_y_no_cambia_nada(db):
    crear_reserva(db, 2, HORA, [6], "2027-03-01", "09:00", "12:00")
    antes = contar(db, *TABLAS_RESERVA)

    with pytest.raises(mysql.connector.Error) as error:
        crear_reserva(db, 1, HORA, [6], "2027-03-01", "11:00", "13:00")

    assert error.value.errno == 1644                    # SIGNAL SQLSTATE '45000'
    assert error.value.msg == "El espacio SR-01 ya está reservado en un horario que se cruza"
    assert contar(db, *TABLAS_RESERVA) == antes         # el ROLLBACK no dejó rastro


def test_espacio_sin_tarifa_deshace_el_espacio_que_si_se_inserto(db):
    antes = contar(db, *TABLAS_RESERVA)

    # El escritorio 3 sí tiene tarifa por día y alcanza a insertarse;
    # la cabina 10 no tiene. Se deshacen los dos y la reserva.
    with pytest.raises(mysql.connector.Error) as error:
        crear_reserva(db, 1, DIA, [3, 10], "2027-03-03")

    assert "CB-01 (Cabina telefónica) no tiene tarifa por Dia" in error.value.msg
    assert contar(db, *TABLAS_RESERVA) == antes


def test_reserva_por_dia_usa_el_horario_de_la_sede_y_reparte_cuotas(db):
    reserva = crear_reserva(db, 1, DIA, [3], "2027-03-02", cuotas=3)

    inicio, fin = fila(db, "SELECT TIME(inicio), TIME(fin) FROM reserva_espacio "
                           "WHERE reserva_id = %s", (reserva,))
    assert str(inicio) == "7:00:00" and str(fin) == "21:00:00"

    cursor = db.cursor()
    cursor.execute("SELECT monto FROM cuota WHERE reserva_id = %s ORDER BY num_cuota", (reserva,))
    montos = [m for (m,) in cursor.fetchall()]
    cursor.close()
    assert len(montos) == 3
    assert sum(montos) == 74500                          # suman exacto el valor
    assert estado(db, reserva) == "PENDIENTE"


@pytest.mark.parametrize("argumentos, mensaje", [
    ((9999, HORA, [3], "2027-03-03", "09:00", "10:00"), "El cliente 9999 no existe"),
    ((1, HORA, [3, 999], "2027-03-03", "09:00", "10:00"), "El espacio 999 no existe"),
    ((1, HORA, [3, 24], "2027-03-03", "09:00", "10:00"),
     "Todos los espacios de una reserva deben ser de la misma sede"),
    ((1, HORA, [3], "2027-03-03", "06:00", "08:00"), "La sede atiende de 07:00 a 21:00"),
    ((1, HORA, [3], "2027-03-03", "10:00", "09:00"),
     "La hora de fin debe ser posterior a la hora de inicio"),
    ((1, HORA, [3], "2020-03-03", "09:00", "10:00"),
     "La fecha de la reserva debe ser hoy o una fecha futura"),
    ((1, HORA, [], "2027-03-03", "09:00", "10:00"), "La reserva debe incluir al menos un espacio"),
])
def test_entradas_invalidas_devuelven_mensaje_claro(db, argumentos, mensaje):
    antes = contar(db, *TABLAS_RESERVA)

    with pytest.raises(mysql.connector.Error) as error:
        crear_reserva(db, *argumentos)

    assert error.value.errno == 1644
    assert error.value.msg == mensaje
    assert contar(db, *TABLAS_RESERVA) == antes


# ------------------------------------------------------------
# T1 sp_registrar_cliente
# ------------------------------------------------------------

def test_empresa_nueva_queda_en_cliente_empresa_y_telefono(db):
    antes = contar(db, *TABLAS_CLIENTE)

    cliente = registrar_cliente(
        db, "EMPRESA", "compras@nubeverde.com.co",
        nit="901445566-7", razon_social="Nube Verde S.A.S.", contacto="Mónica Lozano",
        telefonos=["3015558899", "6017778"],
    )

    despues = contar(db, *TABLAS_CLIENTE)
    assert despues["cliente"] == antes["cliente"] + 1
    assert despues["empresa"] == antes["empresa"] + 1
    assert despues["persona_natural"] == antes["persona_natural"]
    assert despues["telefono_cliente"] == antes["telefono_cliente"] + 2
    assert fila(db, "SELECT tipo_cliente FROM cliente WHERE cliente_id = %s",
                (cliente,))[0] == "EMPRESA"


def test_documento_repetido_no_deja_un_cliente_sin_subclase(db):
    antes = contar(db, *TABLAS_CLIENTE)

    with pytest.raises(mysql.connector.Error) as error:
        registrar_cliente(db, "NATURAL", "ana.perez@gmail.com", documento="70719489",
                          nombres="Ana", apellidos="Pérez Gil", nacimiento="1999-05-10")

    assert error.value.msg == "Ya existe una persona con el documento 70719489"
    assert contar(db, *TABLAS_CLIENTE) == antes
    assert fila(db, "SELECT COUNT(*) FROM cliente WHERE email = 'ana.perez@gmail.com'")[0] == 0


def test_telefono_invalido_deshace_cliente_y_empresa(db):
    antes = contar(db, *TABLAS_CLIENTE)

    with pytest.raises(mysql.connector.Error) as error:
        registrar_cliente(db, "EMPRESA", "info@ferreteriaelsol.com.co",
                          nit="900998877-3", razon_social="Ferretería El Sol Ltda.",
                          contacto="Ricardo Peña", telefonos=["3109998877", "31-ABC"])

    assert "31-ABC no es válido" in error.value.msg
    assert contar(db, *TABLAS_CLIENTE) == antes


def test_menor_de_edad_no_se_registra(db):
    with pytest.raises(mysql.connector.Error) as error:
        registrar_cliente(db, "NATURAL", "tomas.ruiz@gmail.com", documento="1012345678",
                          nombres="Tomás", apellidos="Ruiz Mora", nacimiento="2012-05-10")

    assert error.value.msg == "La persona debe ser mayor de edad para registrarse"


# ------------------------------------------------------------
# T3 sp_registrar_pago y sp_cancelar_reserva
# ------------------------------------------------------------

def test_pagos_en_orden_cambian_el_estado_y_el_saldo(db):
    reserva = crear_reserva(db, 1, DIA, [3], "2027-03-02", cuotas=2)   # 74.500
    assert estado(db, reserva) == "PENDIENTE"

    assert registrar_pago(db, reserva) == (1, 37250)
    assert estado(db, reserva) == "CONFIRMADA"

    assert registrar_pago(db, reserva, "PSE") == (2, 37250)
    assert fila(db, "SELECT fn_saldo_pendiente(%s)", (reserva,))[0] == 0

    with pytest.raises(mysql.connector.Error) as error:
        registrar_pago(db, reserva)
    assert error.value.msg == f"La reserva {reserva} ya tiene todas sus cuotas pagadas"


def test_pago_a_reserva_cancelada_o_inexistente(db):
    with pytest.raises(mysql.connector.Error) as error:
        registrar_pago(db, 7)
    assert error.value.msg == "La reserva 7 está cancelada y no admite pagos"

    with pytest.raises(mysql.connector.Error) as error:
        registrar_pago(db, 99999)
    assert error.value.msg == "La reserva 99999 no existe"


def test_cancelar_libera_el_espacio_y_no_se_cancela_con_pagos(db):
    reserva = crear_reserva(db, 1, HORA, [7], "2027-03-04", "14:00", "16:00")
    libre = "SELECT fn_espacio_disponible(7, '2027-03-04 14:00', '2027-03-04 16:00')"
    assert fila(db, libre)[0] == 0

    db.cursor().callproc("sp_cancelar_reserva", (reserva,))
    assert estado(db, reserva) == "CANCELADA"
    assert fila(db, libre)[0] == 1

    with pytest.raises(mysql.connector.Error) as error:
        db.cursor().callproc("sp_cancelar_reserva", (188,))
    assert "tiene pagos registrados" in error.value.msg
    assert estado(db, 188) == "CONFIRMADA"
