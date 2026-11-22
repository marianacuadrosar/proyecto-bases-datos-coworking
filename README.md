<p align="center">
  <img src="assets/Logo_de_la_Universidad_de_La_Sabana.svg.webp" width="250">
</p>

# Proyecto Final de Bases de Datos
Caso 6: Red de espacios de coworking

CLASE: BASES DE DATOS <br>
DOCENTE: Juan Carlos Rubio Coello <br>
PROGRAMA: Ingeniería Informática <br>

Integrantes:

- Mariana Cuadros Arenas
- Luis Alejandro Muñoz
- Juan Diego Saldarriaga
- Nicolás Rodriguez

Programa: Ingenieria Informática

**23/11/2026**

---

## Contenido del repositorio

| Carpeta | Qué tiene |
|---|---|
| `docs/avance/` | Entrega del avance: supuestos, diccionario, decisiones de diseño, diagrama E/R, modelo relacional y normalización |
| `docs/final/arquitectura.md` | Documento de arquitectura de la aplicación |
| `sql/` | Scripts de MySQL: tablas, datos, consultas, índices, procedimientos, funciones, transacciones y vistas |
| `app/` | Aplicación web (Python + Flask) que usa la base de datos |
| `tests/` | Pruebas automáticas de la aplicación, las validaciones y las transacciones |

La aplicación permite crear, consultar, actualizar y eliminar clientes y reservas, y registrar pagos, sin escribir SQL.
Por dentro solo llama procedimientos almacenados: en el código de la aplicación no hay SQL.

---

## Cómo instalar y ejecutar el sistema desde cero

### Requisitos

- **MySQL Server 8.0.18 o más nuevo** y **MySQL Workbench**.
- **Python 3.10 o más nuevo**. Para comprobarlo: `python --version`.
- **Git**, o descargar el repositorio como ZIP desde GitHub (*Code → Download ZIP*).

### Paso 1. Descargar el proyecto

```bash
git clone https://github.com/marianacuadrosar/proyecto-bases-datos-coworking.git
cd proyecto-bases-datos-coworking
```

### Paso 2. Crear la base de datos

Abra MySQL Workbench, conéctese a su servidor y ejecute estos scripts de la carpeta `sql/` **en este orden**.
Para cada uno: *File → Open SQL Script*, elegir el archivo y pulsar el rayo ⚡ (*Execute*).

| Orden | Script | Qué hace |
|---|---|---|
| 1 | `01_ddl.sql` | Crea la base `coworking_db` y sus 12 tablas con sus restricciones. **Borra la base si ya existía.** |
| 2 | `02_datos_prueba.sql` | Carga los datos de prueba (1.896 filas) |
| 3 | `02_verificacion_datos.sql` | Revisa 20 reglas de los datos; todas deben dar 0 |
| 4 | `03_consultas.sql` | Consultas WHERE / ORDER BY, UPDATE y DELETE |
| 5 | `04_datos_sinteticos.sql` | Agrega 5.000 reservas históricas para medir los índices |
| 6 | `05_indices.sql` | Crea los índices y muestra EXPLAIN antes y después |
| 7 | `06_consultas_analisis.sql` | Consultas INNER JOIN, agregación, GROUP BY y HAVING |
| 8 | `07_procedimientos_funciones.sql` | Funciones y procedimientos con transacción |
| 9 | `08_transacciones.sql` | Demostración de COMMIT y ROLLBACK |
| 10 | `09_consultas_avanzadas.sql` | Subconsultas en WHERE y en FROM, LEFT / RIGHT JOIN y SELF JOIN |
| 11 | `10_vistas_union.sql` | Las 3 vistas y las consultas UNION / UNION ALL |
| 12 | `11_procedimientos_app.sql` | Procedimientos de apoyo para la aplicación |

Todos se ejecutaron en ese orden sobre una base vacía sin ningún error.
**Para usar solo la aplicación bastan los scripts 1, 2, 8, 11 y 12.** Los demás son el banco de consultas y las demostraciones.

### Paso 3. Instalar las dependencias de Python

Desde la carpeta del proyecto:

```bash
python -m venv .venv
```

Activar el entorno virtual:

- Windows (PowerShell): `.venv\Scripts\Activate.ps1`
- Windows (cmd): `.venv\Scripts\activate.bat`
- macOS / Linux: `source .venv/bin/activate`

Instalar las librerías (versiones fijas en `requirements.txt`):

```bash
pip install -r requirements.txt
```

### Paso 4. Configurar la conexión

Copie el archivo `.env.example` con el nombre `.env` y escriba sus datos de MySQL:

```
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=su_contraseña
DB_NAME=coworking_db
FLASK_SECRET_KEY=cualquier-texto-largo
```

El archivo `.env` no se sube a GitHub (está en `.gitignore`), así que ninguna contraseña queda en el repositorio.

### Paso 5. Ejecutar la aplicación

```bash
python app/app.py
```

Abra **http://127.0.0.1:5000** en el navegador. Para detenerla, `Ctrl + C` en la terminal.

### Paso 6. Ejecutar las pruebas automáticas

Con el entorno virtual activo:

```bash
python -m pytest -v
```

Son 35 pruebas y tardan unos 30 segundos:

| Archivo | Pruebas | Qué revisa |
|---|---|---|
| `tests/test_validaciones.py` | 9 | Las validaciones de los formularios (no usa MySQL) |
| `tests/test_app_flujos.py` | 8 | La aplicación de punta a punta: formularios, mensajes y filas de las tablas |
| `tests/test_transacciones.py` | 18 | Los procedimientos, las funciones y los ROLLBACK de `07_procedimientos_funciones.sql` |

Las pruebas **no tocan `coworking_db`**: cada una crea desde cero una base aparte, `coworking_test`, con los mismos scripts.
Usan el usuario y la contraseña del `.env` y necesitan el cliente de consola `mysql`, porque los scripts tienen `DELIMITER`.
En Windows lo buscan solas en `C:\Program Files\MySQL\MySQL Server 8.0\bin`. Si MySQL está en otra carpeta, agréguela al PATH.

---

## Recorrido sugerido para probar el sistema

| Qué probar | Cómo |
|---|---|
| Consultar | *Espacios*: filtrar por ciudad y tipo. *Clientes*: buscar "gmail" o un NIT. *Reservas*: filtrar por estado |
| Crear un cliente | *Nuevo cliente* → persona natural o empresa, con uno o dos teléfonos. Se guarda en 3 tablas en una sola transacción |
| Actualizar | Abrir un cliente → cambiar email o nombre, o agregar un teléfono |
| Crear una reserva | *Nueva reserva* → ciudad, sede, cliente, fecha futura, horario, uno o varios espacios y de 1 a 3 cuotas. Si se paga la cuota 1, queda CONFIRMADA |
| Registrar un pago | Abrir la reserva → *Pagar la siguiente cuota* |
| Finalizar o cancelar | Abrir una reserva → *Finalizar* (si está pagada) o *Cancelar* (si no tiene pagos) |
| Eliminar | Un cliente sin reservas, o una reserva sin pagos |
| **Rollback 1** | Reserve la sala **SR-01** de la **Sede Chapinero** (Bogotá) un día futuro de 9:00 a 12:00. Después intente otra reserva con **EF-01 y SR-01** ese mismo día de 11:00 a 13:00. Aparece *"El espacio SR-01 ya está reservado en un horario que se cruza"* y no se guarda nada, ni siquiera el escritorio que sí estaba libre |
| **Rollback 2** | Registre una persona natural con el documento `70719489`, que ya existe. Aparece *"Ya existe una persona con el documento 70719489"* y el cliente no queda creado |

El documento de arquitectura explica cómo funciona cada flujo por dentro: [docs/final/arquitectura.md](docs/final/arquitectura.md).

---

## Problemas frecuentes

| Mensaje | Solución |
|---|---|
| *No fue posible conectarse a la base de datos* | Revise que el servicio MySQL esté encendido y que el usuario y la contraseña del `.env` sean correctos |
| *Falta un procedimiento en la base de datos* | Ejecute `07_procedimientos_funciones.sql`, `10_vistas_union.sql` y `11_procedimientos_app.sql`, en ese orden |
| `ModuleNotFoundError: No module named 'flask'` | Active el entorno virtual (paso 3) antes de `python app/app.py` |
| `python` no se reconoce | En Windows pruebe con `py` en lugar de `python` |
| Las pruebas fallan con *"mysql" no se reconoce* | Agregue al PATH la carpeta `bin` de su instalación de MySQL |
