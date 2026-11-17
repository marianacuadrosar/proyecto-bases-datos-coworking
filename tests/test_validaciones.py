"""Pruebas de las validaciones de la aplicación (no necesitan MySQL)."""

from datetime import date

import validaciones as v

HOY = date(2026, 11, 17)

CLIENTE_NATURAL = {
    "tipo_cliente": "NATURAL", "email": "laura.rios@gmail.com", "telefono": "3104567890",
    "documento": "1020745332", "nombres": "Laura", "apellidos": "Ríos Pardo",
    "fecha_nacimiento": "1996-08-14",
}

RESERVA_POR_HORA = {
    "cliente_id": "15", "fecha": "2026-12-01", "hora_inicio": "09:00", "hora_fin": "11:00",
    "espacio_1": "18", "espacio_2": "", "espacio_3": "", "anticipo": "", "metodo_pago": "",
}


def test_cliente_valido_no_tiene_errores():
    assert v.validar_cliente(CLIENTE_NATURAL) == []


def test_cliente_con_email_y_telefono_invalidos():
    datos = dict(CLIENTE_NATURAL, email="laura.gmail.com", telefono="31-04")
    errores = v.validar_cliente(datos)
    assert any("email" in e for e in errores)
    assert any("teléfono" in e for e in errores)


def test_menor_de_edad_no_se_registra():
    datos = dict(CLIENTE_NATURAL, fecha_nacimiento="2012-05-01")
    assert "La persona debe ser mayor de edad." in v.validar_cliente(datos)


def test_empresa_con_nit_sin_digito_de_verificacion():
    datos = {"tipo_cliente": "EMPRESA", "email": "info@andina.co", "telefono": "6017654321",
             "nit": "901234567", "razon_social": "Andina S.A.S.", "nombre_contacto": "Ana Gómez"}
    errores = v.validar_cliente(datos)
    assert len(errores) == 1 and "NIT" in errores[0]


def test_reserva_valida_no_tiene_errores():
    assert v.validar_reserva(RESERVA_POR_HORA, "Hora", hoy=HOY) == []


def test_reserva_con_fecha_pasada_y_horas_invertidas():
    datos = dict(RESERVA_POR_HORA, fecha="2026-11-01", hora_inicio="11:00", hora_fin="09:00")
    errores = v.validar_reserva(datos, "Hora", hoy=HOY)
    assert "La fecha de la reserva no puede ser anterior a hoy." in errores
    assert "La hora de fin debe ser posterior a la de inicio." in errores


def test_reserva_por_dia_no_pide_horas():
    datos = dict(RESERVA_POR_HORA, hora_inicio="", hora_fin="")
    assert v.validar_reserva(datos, "Dia", hoy=HOY) == []


def test_reserva_con_espacio_repetido_y_anticipo_sin_metodo():
    datos = dict(RESERVA_POR_HORA, espacio_2="18", anticipo="50000")
    errores = v.validar_reserva(datos, "Hora", hoy=HOY)
    assert "No repita el mismo espacio en la reserva." in errores
    assert "Seleccione el método de pago del anticipo." in errores
