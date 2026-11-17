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

**23/11/2026**

---

## Contenido del repositorio

| Carpeta | Qué tiene |
|---|---|
| `docs/avance/` | Entrega del avance: supuestos, diccionario, decisiones de diseño, diagrama E/R, modelo relacional y normalización |
| `docs/final/arquitectura.md` | Documento de arquitectura de la aplicación |
| `sql/` | Scripts de MySQL: tablas, datos, consultas, índices, vistas y procedimientos |
| `app/` | Aplicación web (Python + Flask) que usa la base de datos |
| `tests/` | Pruebas automáticas de la aplicación y de las transacciones |

La aplicación permite crear, consultar, actualizar y eliminar clientes y reservas, y registrar pagos, sin escribir SQL.
Por dentro solo llama procedimientos almacenados: en el código de la aplicación no hay SQL.

---

## Cómo instalar y ejecutar el sistema desde cero

### Requisitos

- **MySQL Server 8.0.18 o más nuevo** y **MySQL Workbench** (o el cliente `mysql` de consola).
- **Python 3.10 o más nuevo**. Para comprobarlo: `python --version`.
- **Git**, o descargar el repositorio como ZIP desde GitHub (botón *Code → Download ZIP*).

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
| 1 | `01_ddl.sql` | Crea la base `coworking_db` y sus 12 tablas. **Borra la base si ya existía.** |
| 2 | `02_datos_prueba.sql` | Carga los datos de prueba |
| 3 | `02_verificacion_datos.sql` | Revisa 20 reglas de los datos (todas deben dar 0) |
| 4 | `03_consultas.sql` | Consultas WHERE / ORDER BY, UPDATE y DELETE |
| 5 | `04_datos_sinteticos.sql` | Agrega 5.000 reservas históricas para las pruebas de rendimiento |
| 6 | `05_indices.sql` | Crea los índices y muestra EXPLAIN antes y después |
| 7 | `06_consultas_analisis.sql` | Consultas INNER JOIN, agregación, GROUP BY y HAVING |
| 8 | `10_vistas_union.sql` | Crea las 3 vistas y corre las consultas UNION |
| 9 | `11_procedimientos_app.sql` | Crea los procedimientos que usa la aplicación |

Para usar la aplicación bastan los scripts 1, 2, 8 y 9. Los demás son el banco de consultas del proyecto.

> Alternativa por consola (Git Bash, macOS o Linux), desde la carpeta del proyecto.
> Pide la contraseña de MySQL una vez por script:
> ```bash
> for f in 01_ddl 02_datos_prueba 10_vistas_union 11_procedimientos_app; do mysql -u root -p < sql/$f.sql; done
> ```

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

Son 15 pruebas: 8 revisan las validaciones de los formularios y 7 revisan las transacciones contra la base de datos.
Las de base de datos crean sus propios datos en 2027 y los borran al terminar.
Si no hay conexión a MySQL, esas 7 se saltan (*skipped*) en vez de fallar.

---

## Recorrido sugerido para probar el sistema

| Qué probar | Cómo |
|---|---|
| Consultar | *Espacios*: filtrar por ciudad y tipo. *Clientes*: buscar "gmail" o un NIT. *Reservas*: filtrar por estado |
| Crear un cliente | *Nuevo cliente* → persona natural o empresa. Se guarda en 3 tablas en una sola transacción |
| Actualizar | Abrir un cliente → cambiar email o nombre, o agregar un teléfono |
| Crear una reserva | *Nueva reserva* → elegir ciudad, cliente, fecha futura, horario y de 1 a 3 espacios. Con anticipo queda CONFIRMADA |
| Registrar un pago | Abrir la reserva → *Registrar pago* en una cuota pendiente |
| Cambiar el estado | Abrir una reserva PENDIENTE o CONFIRMADA → confirmar, finalizar o cancelar |
| Eliminar | Un cliente sin reservas, o una reserva sin pagos |
| **Rollback 1** | Crear otra reserva con uno de los mismos espacios y un horario que se cruce. Aparece *"El espacio N ya está reservado en ese horario. No se guardó la reserva."* y no queda nada guardado |
| **Rollback 2** | Registrar una persona natural con el documento `70719489`, que ya existe. Aparece *"El documento o NIT ya está registrado en otro cliente. No se guardó ningún dato."* y el cliente no queda creado |

El documento de arquitectura explica cómo funciona cada flujo por dentro: [docs/final/arquitectura.md](docs/final/arquitectura.md).

---

## Usuario de MySQL con permisos mínimos (opcional)

Para no usar `root` en la aplicación se puede crear un usuario que solo pueda leer y ejecutar procedimientos.
Ejecute esto en Workbench con un usuario administrador, cambiando la contraseña:

```sql
CREATE USER 'coworking_app'@'localhost' IDENTIFIED BY 'una-contraseña-segura';
GRANT SELECT, EXECUTE ON coworking_db.* TO 'coworking_app'@'localhost';
```

Después ponga ese usuario en `DB_USER` y `DB_PASSWORD` del `.env`.
La aplicación funciona igual, porque los procedimientos se ejecutan con los permisos de quien los creó.
Las pruebas automáticas sí necesitan un usuario que pueda borrar (por ejemplo `root`), porque limpian lo que crean.

---

## Problemas frecuentes

| Mensaje | Solución |
|---|---|
| *No fue posible conectarse a la base de datos* | Revise que el servicio MySQL esté encendido y que usuario y contraseña del `.env` sean correctos |
| *Falta un procedimiento en la base de datos* | Ejecute `10_vistas_union.sql` y `11_procedimientos_app.sql` (en ese orden) |
| `ModuleNotFoundError: No module named 'flask'` | Active el entorno virtual (paso 3) antes de `python app/app.py` |
| `python` no se reconoce | En Windows pruebe con `py` en lugar de `python` |
