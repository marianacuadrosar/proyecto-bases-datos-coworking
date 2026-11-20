"""Pruebas de las validaciones de la aplicación (no necesitan MySQL)."""

from datetime import date

import validaciones as v

HOY = date(2026, 11, 20)

CLIENTE_NATURAL = {
    "tipo_cliente": "NATURAL", "email": "laura.rios@gmail.com", "telefono": "3104567890",
    "documento": "1020745332", "nombres": "Laura", "apellidos": "Ríos Pardo",
    "fecha_nacimiento": "1996-08-14",
}

RESERVA_POR_HORA = {
    "cliente_id": "15", "fecha": "2026-12-01", "hora_inicio": "09:00", "hora_fin": "11:00",
    "num_cuotas": "1", "metodo_pago": "",
}


def test_cliente_valido_no_tiene_errores():
    assert v.validar_cliente(CLIENTE_NATURAL) == []


def test_cliente_con_email_y_telefono_invalidos():
    datos = dict(CLIENTE_NATURAL, email="laura.gmail.com", telefono="31-04")
    errores = v.validar_cliente(datos)
    assert any("email" in e for e in errores)
    assert any("teléfono" in e for e in errores)


def test_telefono_de_8_digitos_no_es_valido():
    # Igual que en sp_registrar_cliente: 7 dígitos (fijo) o 10 (celular)
    assert v.validar_telefono("31045678") != []
    assert v.validar_telefono("6017654") == []


def test_menor_de_edad_no_se_registra():
    datos = dict(CLIENTE_NATURAL, fecha_nacimiento="2012-05-01")
    assert "La persona debe ser mayor de edad." in v.validar_cliente(datos)


def test_empresa_con_nit_sin_digito_de_verificacion():
    datos = {"tipo_cliente": "EMPRESA", "email": "info@andina.co", "telefono": "6017654321",
             "nit": "901234567", "razon_social": "Andina S.A.S.", "nombre_contacto": "Ana Gómez"}
    errores = v.validar_cliente(datos)
    assert len(errores) == 1 and "NIT" in errores[0]


def test_reserva_valida_no_tiene_errores():
    assert v.validar_reserva(RESERVA_POR_HORA, ["18", "19"], "Hora", hoy=HOY) == []


def test_reserva_con_fecha_pasada_y_horas_invertidas():
    datos = dict(RESERVA_POR_HORA, fecha="2026-11-01", hora_inicio="11:00", hora_fin="09:00")
    errores = v.validar_reserva(datos, ["18"], "Hora", hoy=HOY)
    assert "La fecha de la reserva no puede ser anterior a hoy." in errores
    assert "La hora de fin debe ser posterior a la de inicio." in errores


def test_reserva_por_dia_no_pide_horas():
    datos = dict(RESERVA_POR_HORA, hora_inicio="", hora_fin="")
    assert v.validar_reserva(datos, ["18"], "Dia", hoy=HOY) == []


def test_reserva_sin_espacios_y_con_cuotas_fuera_de_rango():
    datos = dict(RESERVA_POR_HORA, num_cuotas="5", metodo_pago="Bitcoin")
    errores = v.validar_reserva(datos, [], "Hora", hoy=HOY)
    assert "Marque al menos un espacio." in errores
    assert "El número de cuotas debe ser 1, 2 o 3." in errores
    assert "El método de pago no es válido." in errores
