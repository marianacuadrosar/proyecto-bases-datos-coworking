"""
Configuración común de las pruebas.

Antes de cada prueba se crea desde cero una base aparte,
coworking_test, con los mismos scripts del proyecto:

    sql/01_ddl.sql
    sql/02_datos_prueba.sql
    sql/07_procedimientos_funciones.sql

Así cada prueba empieza con los mismos datos y nunca se toca la base
real coworking_db.

La conexión se configura con variables de entorno (todas opcionales):

    DB_HOST      localhost
    DB_PORT      3306
    DB_USER      root
    DB_PASSWORD  (vacía)

Requiere el cliente de consola `mysql` instalado, porque los scripts
usan DELIMITER y eso solo lo entiende la consola, no el conector.
"""

import os
import re
import subprocess
from pathlib import Path

import mysql.connector
import pytest

RAIZ = Path(__file__).resolve().parent.parent
BASE_PRUEBAS = "coworking_test"

SCRIPTS = [
    RAIZ / "sql" / "01_ddl.sql",
    RAIZ / "sql" / "02_datos_prueba.sql",
    RAIZ / "sql" / "07_procedimientos_funciones.sql",
]

CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
}


def _cambiar_base(sql: str) -> str:
    """Hace que el script cree y use coworking_test en vez de coworking_db."""
    return re.sub(r"\bcoworking_db\b", BASE_PRUEBAS, sql)


def _ejecutar_script(ruta: Path) -> None:
    sql = _cambiar_base(ruta.read_text(encoding="utf-8"))
    comando = [
        "mysql",
        f"--host={CONFIG['host']}",
        f"--port={CONFIG['port']}",
        f"--user={CONFIG['user']}",
        "--default-character-set=utf8mb4",
    ]
    entorno = dict(os.environ, MYSQL_PWD=CONFIG["password"])
    resultado = subprocess.run(
        comando, input=sql, text=True, encoding="utf-8",
        capture_output=True, env=entorno,
    )
    if resultado.returncode != 0:
        raise RuntimeError(f"Falló {ruta.name}:\n{resultado.stderr}")


@pytest.fixture
def db():
    """Base recién creada y una conexión con autocommit.

    Con autocommit cada CALL maneja su propia transacción, igual que
    cuando la aplicación llama a los procedimientos.
    """
    for script in SCRIPTS:
        _ejecutar_script(script)

    conexion = mysql.connector.connect(
        **CONFIG, database=BASE_PRUEBAS, autocommit=True, charset="utf8mb4"
    )
    yield conexion
    conexion.close()


def contar(conexion, *tablas):
    """Devuelve {tabla: número de filas}."""
    cursor = conexion.cursor()
    conteo = {}
    for tabla in tablas:
        cursor.execute(f"SELECT COUNT(*) FROM {tabla}")
        conteo[tabla] = cursor.fetchone()[0]
    cursor.close()
    return conteo


def fila(conexion, consulta, parametros=()):
    """Ejecuta una consulta y devuelve la primera fila."""
    cursor = conexion.cursor()
    cursor.execute(consulta, parametros)
    resultado = cursor.fetchone()
    cursor.fetchall()
    cursor.close()
    return resultado
