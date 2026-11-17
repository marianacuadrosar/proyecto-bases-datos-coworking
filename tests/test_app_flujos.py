"""Pruebas de integración de los flujos transaccionales.

Llaman los mismos procedimientos que usa la aplicación, contra la base
coworking_db del archivo .env. Las reservas se crean en 2027 para no
chocar con los datos de prueba.
"""

import pytest

from conftest import consultar, contar_filas
from db import ErrorBD, llamar

FECHA = "2027-06-15"


def crear_reserva(cliente_id, modalidad_id, espacios, anticipo=0, metodo=None,
                  hora_inicio="09:00", hora_fin="11:00"):
    espacios = list(espacios) + [None] * (3 - len(espacios))
    _, salida = llamar("sp_app_crear_reserva", cliente_id, modalidad_id, FECHA,
                       hora_inicio, hora_fin, *espacios, anticipo, metodo, None)
    return salida[-1]


def test_crear_reserva_con_anticipo_guarda_las_tres_tablas(espacios_libres, modalidad_hora, limpiar):
    e1, _ = espacios_libres
    reserva_id = crear_reserva(1, modalidad_hora, [e1], anticipo=10000, metodo="Nequi")
    limpiar["reservas"].append(reserva_id)

    estado = consultar("SELECT estado FROM reserva WHERE reserva_id = %s", reserva_id)
    espacios = consultar("SELECT COUNT(*) FROM reserva_espacio WHERE reserva_id = %s", reserva_id)
    cuotas = consultar("SELECT num_cuota, fecha_pago IS NOT NULL FROM cuota "
                       "WHERE reserva_id = %s ORDER BY num_cuota", reserva_id)

    assert estado[0][0] == "CONFIRMADA"
    assert espacios[0][0] == 1
    assert cuotas == [(1, 1), (2, 0)]  # anticipo pagado y saldo pendiente


def test_rollback_reserva_con_espacio_ocupado_no_deja_cambios(espacios_libres, modalidad_hora, limpiar):
    e1, e2 = espacios_libres
    # Primero se ocupa e2 de 09:00 a 11:00.
    limpiar["reservas"].append(crear_reserva(1, modalidad_hora, [e2]))
    antes = contar_filas()

    # La nueva reserva inserta RESERVA y el espacio e1 (libre) antes de
    # descubrir que e2 se cruza de 10:00 a 12:00. El ROLLBACK debe
    # deshacer esos dos INSERT.
    with pytest.raises(ErrorBD, match="ya está reservado en ese horario"):
        crear_reserva(1, modalidad_hora, [e1, e2], hora_inicio="10:00", hora_fin="12:00")

    assert contar_filas() == antes


def test_rollback_anticipo_mayor_al_total(espacios_libres, modalidad_hora):
    e1, _ = espacios_libres
    antes = contar_filas()

    with pytest.raises(ErrorBD, match="anticipo no puede superar"):
        crear_reserva(1, modalidad_hora, [e1], anticipo=999999999, metodo="PSE")

    assert contar_filas() == antes


def test_rollback_cliente_con_documento_repetido_no_deja_cliente(bd):
    documento_existente = consultar("SELECT documento FROM persona_natural LIMIT 1")[0][0]
    antes = contar_filas()

    # El INSERT en CLIENTE sí se ejecuta; el de PERSONA_NATURAL falla por
    # el UNIQUE del documento y el ROLLBACK debe borrar el cliente.
    with pytest.raises(ErrorBD, match="documento o NIT ya está registrado"):
        llamar("sp_app_registrar_cliente", "NATURAL", "prueba.rollback@ejemplo.com", "3001112233",
               documento_existente, "Prueba", "Rollback", "1990-01-01", None, None, None, None)

    assert contar_filas() == antes
    assert consultar("SELECT COUNT(*) FROM cliente WHERE email = 'prueba.rollback@ejemplo.com'")[0][0] == 0


def test_registrar_empresa_guarda_las_tres_tablas(limpiar):
    _, salida = llamar("sp_app_registrar_cliente", "EMPRESA", "contacto@pruebaautomatica.co",
                       "6015550000", None, None, None, None, "999888777-1",
                       "Prueba Automática S.A.S.", "Ana Prueba", None)
    cliente_id = salida[-1]
    limpiar["clientes"].append(cliente_id)

    assert consultar("SELECT tipo_cliente FROM cliente WHERE cliente_id = %s", cliente_id)[0][0] == "EMPRESA"
    assert consultar("SELECT nit FROM empresa WHERE cliente_id = %s", cliente_id)[0][0] == "999888777-1"
    assert consultar("SELECT COUNT(*) FROM telefono_cliente WHERE cliente_id = %s", cliente_id)[0][0] == 1


def test_pagar_cuota_confirma_una_reserva_pendiente(espacios_libres, modalidad_hora, limpiar):
    e1, _ = espacios_libres
    reserva_id = crear_reserva(1, modalidad_hora, [e1])  # sin anticipo: PENDIENTE
    limpiar["reservas"].append(reserva_id)

    llamar("sp_app_pagar_cuota", reserva_id, 1, "Efectivo")

    assert consultar("SELECT estado FROM reserva WHERE reserva_id = %s", reserva_id)[0][0] == "CONFIRMADA"
    assert consultar("SELECT fecha_pago IS NOT NULL FROM cuota WHERE reserva_id = %s", reserva_id)[0][0] == 1


def test_no_se_elimina_un_cliente_con_reservas(bd):
    cliente_con_reservas = consultar("SELECT cliente_id FROM reserva LIMIT 1")[0][0]

    with pytest.raises(ErrorBD, match="No se puede eliminar"):
        llamar("sp_app_eliminar_cliente", cliente_con_reservas)

    assert consultar("SELECT COUNT(*) FROM cliente WHERE cliente_id = %s", cliente_con_reservas)[0][0] == 1
