"""Validaciones de los formularios.

Se revisan antes de llamar a la base de datos para dar un mensaje
inmediato y no gastar una conexión en datos que de todas formas
fallarían. La base de datos vuelve a revisar lo importante (CHECK,
NOT NULL, UNIQUE y SIGNAL en los procedimientos), porque la aplicación
no es la única forma de escribir en ella.

Cada función recibe los datos del formulario y devuelve una lista de
errores. Si la lista está vacía, los datos son válidos.
"""

import re
from datetime import date, datetime

METODOS_PAGO = ["Efectivo", "Nequi", "PSE", "Tarjeta de crédito",
                "Tarjeta débito", "Transferencia"]

PATRON_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$")
PATRON_TELEFONO = re.compile(r"^(\d{7}|\d{10})$")
PATRON_DOCUMENTO = re.compile(r"^\d{6,10}$")
PATRON_NIT = re.compile(r"^\d{9}-\d$")


def texto(datos, campo):
    """Devuelve el campo sin espacios a los lados ('' si no viene)."""
    return (datos.get(campo) or "").strip()


def entero_opcional(valor):
    """Convierte a int; '' o None quedan como None. Lanza ValueError si no es número."""
    valor = (valor or "").strip()
    return int(valor) if valor else None


def validar_email(email):
    if not email:
        return ["El email es obligatorio."]
    if len(email) > 100 or not PATRON_EMAIL.match(email):
        return ["El email no tiene un formato válido (ejemplo: nombre@dominio.com)."]
    return []


def validar_telefono(telefono, obligatorio=True):
    if not telefono:
        return ["El teléfono es obligatorio."] if obligatorio else []
    if not PATRON_TELEFONO.match(telefono):
        return ["El teléfono debe tener 7 dígitos (fijo) o 10 (celular), sin espacios."]
    return []


def validar_cliente(datos):
    """Formulario de cliente nuevo (persona natural o empresa)."""
    errores = []
    tipo = texto(datos, "tipo_cliente")
    if tipo not in ("NATURAL", "EMPRESA"):
        return ["Seleccione si el cliente es persona natural o empresa."]

    errores += validar_email(texto(datos, "email"))
    errores += validar_telefono(texto(datos, "telefono"))
    errores += validar_telefono(texto(datos, "telefono_2"), obligatorio=False)

    if tipo == "NATURAL":
        if not PATRON_DOCUMENTO.match(texto(datos, "documento")):
            errores.append("El documento debe tener entre 6 y 10 dígitos.")
        errores += validar_nombres(datos)
        nacimiento = texto(datos, "fecha_nacimiento")
        try:
            fecha = datetime.strptime(nacimiento, "%Y-%m-%d").date()
            if edad(fecha) < 18:
                errores.append("La persona debe ser mayor de edad.")
            elif edad(fecha) > 110:
                errores.append("La fecha de nacimiento no es válida.")
        except ValueError:
            errores.append("La fecha de nacimiento es obligatoria (AAAA-MM-DD).")
    else:
        if not PATRON_NIT.match(texto(datos, "nit")):
            errores.append("El NIT debe tener 9 dígitos, guion y dígito de verificación (ejemplo: 900123456-7).")
        errores += validar_empresa(datos)
    return errores


def validar_nombres(datos):
    errores = []
    if not texto(datos, "nombres") or len(texto(datos, "nombres")) > 60:
        errores.append("Los nombres son obligatorios (máximo 60 caracteres).")
    if not texto(datos, "apellidos") or len(texto(datos, "apellidos")) > 60:
        errores.append("Los apellidos son obligatorios (máximo 60 caracteres).")
    return errores


def validar_empresa(datos):
    errores = []
    if not texto(datos, "razon_social") or len(texto(datos, "razon_social")) > 120:
        errores.append("La razón social es obligatoria (máximo 120 caracteres).")
    if not texto(datos, "nombre_contacto") or len(texto(datos, "nombre_contacto")) > 100:
        errores.append("El nombre de contacto es obligatorio (máximo 100 caracteres).")
    return errores


def validar_edicion_cliente(datos, tipo):
    """Formulario de edición: email, nombre y un teléfono nuevo opcional."""
    errores = validar_email(texto(datos, "email"))
    errores += validar_telefono(texto(datos, "telefono_nuevo"), obligatorio=False)
    errores += validar_nombres(datos) if tipo == "NATURAL" else validar_empresa(datos)
    return errores


def edad(nacimiento, hoy=None):
    hoy = hoy or date.today()
    return hoy.year - nacimiento.year - ((hoy.month, hoy.day) < (nacimiento.month, nacimiento.day))


def telefonos(datos):
    """Teléfonos del formulario de cliente nuevo, sin vacíos ni repetidos."""
    lista = [texto(datos, "telefono"), texto(datos, "telefono_2")]
    return list(dict.fromkeys(t for t in lista if t))


def validar_reserva(datos, espacios, nombre_modalidad, hoy=None):
    """Formulario de reserva nueva.

    espacios es la lista de espacio_id marcados en el formulario y
    nombre_modalidad es 'Hora' o 'Dia'.
    """
    errores = []
    hoy = hoy or date.today()

    try:
        if entero_opcional(datos.get("cliente_id")) is None:
            errores.append("Seleccione el cliente.")
    except ValueError:
        errores.append("El cliente no es válido.")

    if nombre_modalidad not in ("Hora", "Dia"):
        errores.append("Seleccione la modalidad.")

    try:
        fecha = datetime.strptime(texto(datos, "fecha"), "%Y-%m-%d").date()
        if fecha < hoy:
            errores.append("La fecha de la reserva no puede ser anterior a hoy.")
    except ValueError:
        errores.append("La fecha es obligatoria (AAAA-MM-DD).")

    if nombre_modalidad == "Hora":
        try:
            inicio = datetime.strptime(texto(datos, "hora_inicio"), "%H:%M").time()
            fin = datetime.strptime(texto(datos, "hora_fin"), "%H:%M").time()
            if fin <= inicio:
                errores.append("La hora de fin debe ser posterior a la de inicio.")
        except ValueError:
            errores.append("Por hora, indique hora de inicio y hora de fin (HH:MM).")

    if not espacios:
        errores.append("Marque al menos un espacio.")
    elif not all(str(e).isdigit() for e in espacios):
        errores.append("Los espacios marcados no son válidos.")
    elif len(espacios) != len(set(espacios)):
        errores.append("No repita el mismo espacio en la reserva.")

    if texto(datos, "num_cuotas") not in ("1", "2", "3"):
        errores.append("El número de cuotas debe ser 1, 2 o 3.")

    metodo = texto(datos, "metodo_pago")
    if metodo and metodo not in METODOS_PAGO:
        errores.append("El método de pago no es válido.")
    return errores
