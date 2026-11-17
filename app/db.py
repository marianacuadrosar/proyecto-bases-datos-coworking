"""Conexión con MySQL.

La aplicación solo habla con la base de datos a través de la función
llamar(), que ejecuta un procedimiento almacenado. En el código de la
aplicación no hay SQL escrito a mano.
"""

import os

import mysql.connector
from dotenv import load_dotenv

# Las credenciales están en el archivo .env de la raíz del proyecto,
# que no se sube a GitHub.
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(RAIZ, ".env"))


class ErrorBD(Exception):
    """Error de la base de datos con un mensaje claro para el usuario."""


def conectar():
    """Abre una conexión nueva con los datos del archivo .env."""
    try:
        return mysql.connector.connect(
            host=os.getenv("DB_HOST", "127.0.0.1"),
            port=int(os.getenv("DB_PORT", "3306")),
            user=os.getenv("DB_USER", "root"),
            password=os.getenv("DB_PASSWORD", ""),
            database=os.getenv("DB_NAME", "coworking_db"),
            charset="utf8mb4",
            # Cada procedimiento abre y cierra su propia transacción,
            # así que la aplicación no deja transacciones abiertas.
            autocommit=True,
        )
    except mysql.connector.Error as error:
        raise ErrorBD(traducir_error(error)) from error


def traducir_error(error):
    """Convierte un error de MySQL en un mensaje que el usuario entienda."""
    if error.errno == 1644:
        # SIGNAL SQLSTATE '45000' de un procedimiento: el mensaje ya
        # viene escrito para el usuario.
        return error.msg
    if error.errno == 1062:
        return "Ese dato ya está registrado y no se puede repetir."
    if error.errno in (1451, 1452):
        return "La operación rompe una relación con otros datos (llave foránea)."
    if error.errno == 3819:
        return "Un valor no cumple las reglas de la base de datos (restricción CHECK)."
    if error.errno in (1045, 2003, 2005, 1049):
        return ("No fue posible conectarse a la base de datos. "
                "Revise que MySQL esté encendido y los datos del archivo .env.")
    if error.errno == 1305:
        return ("Falta un procedimiento en la base de datos. "
                "Ejecute los scripts SQL en el orden del README.")
    return f"Error de la base de datos ({error.errno}). No se guardaron cambios."


def llamar(procedimiento, *parametros):
    """Ejecuta un procedimiento almacenado.

    Devuelve una tupla (tablas, salida):
      tablas  lista de resultados; cada uno es una lista de diccionarios.
      salida  los parámetros después de la llamada (ahí llegan los OUT).
    """
    conexion = conectar()
    cursor = conexion.cursor()
    try:
        salida = cursor.callproc(procedimiento, parametros)
        tablas = []
        for resultado in cursor.stored_results():
            columnas = resultado.column_names
            tablas.append([dict(zip(columnas, fila)) for fila in resultado.fetchall()])
        return tablas, salida
    except mysql.connector.Error as error:
        raise ErrorBD(traducir_error(error)) from error
    finally:
        cursor.close()
        conexion.close()
