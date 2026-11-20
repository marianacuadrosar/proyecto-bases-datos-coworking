"""Pruebas de la aplicación web de punta a punta.

Usan el cliente de pruebas de Flask: envían los mismos formularios que
llenaría el profesor en el navegador y revisan la página que responde
y las filas de las tablas.

Cada prueba trabaja sobre la base coworking_test, que el fixture db de
conftest.py crea desde cero con 01, 02 y 07. Aquí se le agregan las
vistas (10) y los procedimientos de la aplicación (11).

Datos de partida (sql/02_datos_prueba.sql), Sede Chapinero (sede 1, Bogotá):
    espacio 6  SR-01 sala de reuniones    68.500 por hora
    espacio 1  EF-01 escritorio flexible  12.000 por hora
    cliente 1  Andrés Patiño, documento 70719489
    cliente 2  Tequendama Ingeniería S.A.S. (tiene reservas)
Las reservas se hacen en marzo de 2027, que no tiene reservas.
"""

import pytest

import app as aplicacion
from conftest import RAIZ, _ejecutar_script, contar, fila

TABLAS = ("cliente", "persona_natural", "empresa", "telefono_cliente",
          "reserva", "reserva_espacio", "cuota")

RESERVA = {
    "ciudad": "Bogotá", "sede_id": "1", "cliente_id": "2", "modalidad_id": "1",
    "fecha": "2027-03-01", "hora_inicio": "09:00", "hora_fin": "12:00",
    "espacios": ["6", "1"], "num_cuotas": "2", "metodo_pago": "Transferencia",
}


@pytest.fixture
def navegador(db, monkeypatch):
    """Cliente de Flask conectado a coworking_test."""
    for script in ("10_vistas_union.sql", "11_procedimientos_app.sql"):
        _ejecutar_script(RAIZ / "sql" / script)
    monkeypatch.setenv("DB_NAME", "coworking_test")
    aplicacion.app.config["TESTING"] = True
    return aplicacion.app.test_client()


def texto(respuesta):
    return respuesta.get_data(as_text=True)


def test_paginas_de_consulta_responden(navegador):
    for url in ("/", "/espacios?ciudad=Bogotá", "/clientes?buscar=gmail",
                "/reservas?estado=CONFIRMADA", "/clientes/2", "/reservas/188",
                "/reservas/nueva?ciudad=Bogotá&sede_id=1"):
        assert navegador.get(url).status_code == 200, url


def test_crear_reserva_desde_la_app_guarda_las_tres_tablas(navegador, db):
    antes = contar(db, *TABLAS)

    respuesta = navegador.post("/reservas/nueva", data=RESERVA, follow_redirects=True)

    despues = contar(db, *TABLAS)
    assert "creada" in texto(respuesta) and "CONFIRMADA" in texto(respuesta)
    assert despues["reserva"] == antes["reserva"] + 1
    assert despues["reserva_espacio"] == antes["reserva_espacio"] + 2
    assert despues["cuota"] == antes["cuota"] + 2


def test_rollback_reserva_con_cruce_muestra_el_mensaje_y_no_guarda_nada(navegador, db):
    navegador.post("/reservas/nueva", data=RESERVA)
    antes = contar(db, *TABLAS)

    # El escritorio EF-01 está libre de 11 a 13, pero la sala SR-01 ya
    # está ocupada de 9 a 12. sp_crear_reserva alcanza a insertar y hace
    # ROLLBACK de todo.
    choque = dict(RESERVA, hora_inicio="11:00", hora_fin="13:00", espacios=["1", "6"])
    respuesta = navegador.post("/reservas/nueva", data=choque)

    assert respuesta.status_code == 200
    assert "ya está reservado en un horario que se cruza" in texto(respuesta)
    assert contar(db, *TABLAS) == antes


def test_formulario_invalido_no_llega_a_la_base(navegador, db):
    antes = contar(db, *TABLAS)

    malo = dict(RESERVA, fecha="2020-01-01", espacios=[])
    respuesta = navegador.post("/reservas/nueva", data=malo)

    assert "La fecha de la reserva no puede ser anterior a hoy." in texto(respuesta)
    assert "Marque al menos un espacio." in texto(respuesta)
    assert contar(db, *TABLAS) == antes


def test_rollback_cliente_con_documento_repetido(navegador, db):
    antes = contar(db, *TABLAS)

    respuesta = navegador.post("/clientes/nuevo", data={
        "tipo_cliente": "NATURAL", "email": "otra.persona@gmail.com", "telefono": "3001112233",
        "documento": "70719489", "nombres": "Otra", "apellidos": "Persona",
        "fecha_nacimiento": "1990-01-01"})

    assert "Ya existe una persona con el documento 70719489" in texto(respuesta)
    assert contar(db, *TABLAS) == antes          # tampoco quedó la fila en cliente


def test_registrar_empresa_con_dos_telefonos(navegador, db):
    antes = contar(db, *TABLAS)

    respuesta = navegador.post("/clientes/nuevo", follow_redirects=True, data={
        "tipo_cliente": "EMPRESA", "email": "compras@pruebaweb.com.co",
        "telefono": "3015558899", "telefono_2": "6017778899", "nit": "901445566-7",
        "razon_social": "Prueba Web S.A.S.", "nombre_contacto": "Mónica Lozano"})

    despues = contar(db, *TABLAS)
    assert "registrado" in texto(respuesta)
    assert despues["cliente"] == antes["cliente"] + 1
    assert despues["empresa"] == antes["empresa"] + 1
    assert despues["telefono_cliente"] == antes["telefono_cliente"] + 2


def test_pagar_todas_las_cuotas_y_finalizar(navegador, db):
    sin_pago = dict(RESERVA, metodo_pago="", espacios=["6"])
    respuesta = navegador.post("/reservas/nueva", data=sin_pago)
    reserva_id = int(respuesta.headers["Location"].rsplit("/", 1)[1])
    assert fila(db, "SELECT estado FROM reserva WHERE reserva_id = %s", (reserva_id,))[0] == "PENDIENTE"

    for _ in range(2):
        navegador.post(f"/reservas/{reserva_id}/pagar", data={"metodo_pago": "Nequi"})
    respuesta = navegador.post(f"/reservas/{reserva_id}/finalizar", follow_redirects=True)

    assert "finalizada" in texto(respuesta)
    assert fila(db, "SELECT estado FROM reserva WHERE reserva_id = %s", (reserva_id,))[0] == "FINALIZADA"


def test_no_se_elimina_un_cliente_con_reservas(navegador, db):
    respuesta = navegador.post("/clientes/2/eliminar", follow_redirects=True)

    assert "No se puede eliminar" in texto(respuesta)
    assert fila(db, "SELECT COUNT(*) FROM cliente WHERE cliente_id = 2")[0] == 1
