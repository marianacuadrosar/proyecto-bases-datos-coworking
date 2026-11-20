"""Preparación de las pruebas, antes de cargar tests/conftest.py.

1. Carga el archivo .env para que DB_USER y DB_PASSWORD lleguen a las
   pruebas sin tener que escribirlos en la terminal.
2. Si el cliente de consola `mysql` no está en el PATH (pasa en Windows
   con la instalación por defecto), agrega la carpeta donde suele estar.
   Las pruebas lo usan para cargar los scripts, que tienen DELIMITER.
"""

import glob
import os
import shutil

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

if shutil.which("mysql") is None:
    for carpeta in sorted(glob.glob(r"C:\Program Files\MySQL\MySQL Server *\bin"), reverse=True):
        if os.path.exists(os.path.join(carpeta, "mysql.exe")):
            os.environ["PATH"] = carpeta + os.pathsep + os.environ["PATH"]
            break
