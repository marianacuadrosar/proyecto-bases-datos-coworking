#!/usr/bin/env python3
"""
Genera 02_datos_prueba.sql para coworking_db (Caso 6: red de espacios de coworking).

La semilla es fija: cada ejecución produce exactamente el mismo archivo.
Uso:  python3 generar_datos.py > 02_datos_prueba.sql
"""
import random
import datetime as dt
import unicodedata
from collections import defaultdict

random.seed(20261116)
HOY = dt.date(2026, 11, 16)          # fecha de corte de los datos
INICIO_DATOS = dt.date(2025, 1, 8)   # primera reserva realista


# ------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------
def q(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"


def v(x):
    if x is None:
        return "NULL"
    if isinstance(x, int):
        return str(x)
    if isinstance(x, dt.datetime):
        return q(x.strftime("%Y-%m-%d %H:%M:%S"))
    if isinstance(x, dt.date):
        return q(x.isoformat())
    if isinstance(x, dt.time):
        return q(x.strftime("%H:%M:%S"))
    return q(x)


def ascii_slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(c for c in s.lower() if c.isalnum() or c in ".")


def redondear(valor):
    if valor < 100_000:
        paso = 500
    elif valor < 1_000_000:
        paso = 5_000
    else:
        paso = 10_000
    return int(round(valor / paso) * paso)


def no_domingo(d):
    return d + dt.timedelta(days=1) if d.weekday() == 6 else d


def t(hhmm):
    h, m = map(int, hhmm.split(":"))
    return dt.time(h, m)


# ------------------------------------------------------------------
# Catálogos
# ------------------------------------------------------------------
MODALIDADES = [(1, "Hora"), (2, "Dia")]

# id, nombre, descripción, capacidades posibles, tarifa base hora, tarifa base día
TIPOS = [
    (1, "Escritorio flexible", "Puesto sin asignar en zona abierta", [1], 12_000, 55_000),
    (2, "Escritorio dedicado", "Puesto fijo con cajonera y casillero", [1], 16_000, 75_000),
    (3, "Oficina privada", "Oficina cerrada para equipos pequeños", [2, 4, 6, 8], 45_000, 280_000),
    (4, "Sala de reuniones", "Sala con pantalla y videoconferencia", [4, 6, 8, 10, 12], 70_000, 420_000),
    (5, "Sala de capacitación", "Salón con mesas modulares y proyector", [12, 16, 20, 24], 140_000, 850_000),
    (6, "Auditorio", "Espacio para eventos con sonido y tarima", [40, 60, 80], 260_000, 1_600_000),
    (7, "Cabina telefónica", "Cabina insonorizada para llamadas", [1], 9_000, None),
]
TIPO = {x[0]: x for x in TIPOS}
PREFIJO = {1: "EF", 2: "ED", 3: "OF", 4: "SR", 5: "SC", 6: "AUD", 7: "CB"}

CIUDADES = {
    # ciudad: (indicativo fijo, multiplicador de precio)
    "Bogotá": ("601", 1.00), "Medellín": ("604", 0.95), "Cali": ("602", 0.85),
    "Barranquilla": ("605", 0.85), "Cartagena": ("605", 0.95), "Bucaramanga": ("607", 0.80),
    "Pereira": ("606", 0.75), "Manizales": ("606", 0.75), "Santa Marta": ("605", 0.80),
    "Cúcuta": ("607", 0.70), "Ibagué": ("608", 0.70), "Villavicencio": ("608", 0.70),
    "Pasto": ("602", 0.70), "Armenia": ("606", 0.70), "Neiva": ("608", 0.70),
}

# nombre, calle, número, barrio, ciudad, apertura, cierre, premium, tamaño (G/M/P)
SEDES = [
    ("Sede Chapinero", "Calle 57", "9-29", "Chapinero", "Bogotá", "07:00", "21:00", False, "G"),
    ("Sede Quinta Camacho", "Carrera 9", "69-70", "Quinta Camacho", "Bogotá", "07:00", "20:00", False, "M"),
    ("Sede Parque 93", "Calle 93B", "13-47", "Chicó Norte", "Bogotá", "06:00", "22:00", True, "G"),
    ("Sede Usaquén", "Carrera 6", "119-24", "Usaquén", "Bogotá", "07:00", "20:00", False, "M"),
    ("Sede Santa Bárbara", "Calle 116", "15-36", "Santa Bárbara", "Bogotá", "07:00", "21:00", True, "G"),
    ("Sede Cedritos", "Calle 140", "11-45", "Cedritos", "Bogotá", "07:00", "20:00", False, "M"),
    ("Sede La Candelaria", "Carrera 4", "12-40", "La Candelaria", "Bogotá", "08:00", "19:00", False, "M"),
    ("Sede Teusaquillo", "Calle 39", "17-21", "Teusaquillo", "Bogotá", "07:00", "20:00", False, "M"),
    ("Sede Ciudad Salitre", "Calle 24", "69-59", "Ciudad Salitre", "Bogotá", "06:30", "21:00", False, "G"),
    ("Sede Galerías", "Calle 53", "27-16", "Galerías", "Bogotá", "07:00", "20:00", False, "M"),
    ("Sede Colina", "Calle 138", "55-24", "Colina Campestre", "Bogotá", "07:00", "20:00", False, "G"),
    ("Sede Modelia", "Carrera 75", "24C-15", "Modelia", "Bogotá", "07:00", "19:00", False, "G"),
    ("Sede Zona T", "Carrera 13", "82-71", "El Retiro", "Bogotá", "06:00", "22:00", True, "G"),
    ("Sede Calle 100", "Calle 100", "8A-49", "Chicó Navarra", "Bogotá", "06:30", "21:00", True, "G"),
    ("Sede El Poblado", "Carrera 43A", "7-50", "El Poblado", "Medellín", "06:00", "22:00", True, "G"),
    ("Sede Provenza", "Carrera 35", "8A-76", "Provenza", "Medellín", "07:00", "21:00", True, "G"),
    ("Sede Manila", "Calle 11", "43B-26", "Manila", "Medellín", "07:00", "20:00", False, "M"),
    ("Sede Ciudad del Río", "Carrera 48", "20-34", "Ciudad del Río", "Medellín", "06:30", "21:00", False, "G"),
    ("Sede Laureles", "Circular 1", "70-08", "Laureles", "Medellín", "07:00", "20:00", False, "G"),
    ("Sede Estadio", "Carrera 70", "44-35", "Estadio", "Medellín", "07:00", "20:00", False, "M"),
    ("Sede Conquistadores", "Calle 34", "65-19", "Conquistadores", "Medellín", "07:00", "20:00", False, "M"),
    ("Sede Belén", "Carrera 76", "30A-12", "Belén", "Medellín", "07:00", "19:00", False, "M"),
    ("Sede Calasanz", "Carrera 81", "49-30", "Calasanz", "Medellín", "07:00", "19:00", False, "M"),
    ("Sede Granada", "Avenida 9 Norte", "15-24", "Granada", "Cali", "07:00", "21:00", True, "G"),
    ("Sede San Fernando", "Carrera 34", "3-89", "San Fernando", "Cali", "07:00", "20:00", False, "M"),
    ("Sede Ciudad Jardín", "Carrera 105", "14-42", "Ciudad Jardín", "Cali", "07:00", "20:00", False, "M"),
    ("Sede El Peñón", "Calle 2 Oeste", "3-48", "El Peñón", "Cali", "07:00", "20:00", False, "M"),
    ("Sede Versalles", "Avenida 4 Norte", "21-35", "Versalles", "Cali", "07:30", "19:30", False, "P"),
    ("Sede Santa Mónica", "Avenida 6 Norte", "28N-10", "Santa Mónica", "Cali", "07:30", "19:30", False, "P"),
    ("Sede Alto Prado", "Carrera 53", "76-115", "Alto Prado", "Barranquilla", "07:00", "21:00", True, "G"),
    ("Sede El Prado", "Calle 58", "58-31", "El Prado", "Barranquilla", "07:00", "20:00", False, "M"),
    ("Sede Riomar", "Carrera 51B", "106-50", "Riomar", "Barranquilla", "07:00", "20:00", False, "M"),
    ("Sede Villa Country", "Calle 77", "65-37", "Villa Country", "Barranquilla", "07:30", "19:30", False, "P"),
    ("Sede Cabecera", "Carrera 33", "48-25", "Cabecera del Llano", "Bucaramanga", "07:00", "20:00", False, "M"),
    ("Sede Sotomayor", "Calle 48", "28-40", "Sotomayor", "Bucaramanga", "07:30", "19:30", False, "P"),
    ("Sede La Aurora", "Carrera 27", "36-14", "La Aurora", "Bucaramanga", "07:30", "19:30", False, "P"),
    ("Sede Bocagrande", "Carrera 2", "8-145", "Bocagrande", "Cartagena", "07:00", "21:00", True, "M"),
    ("Sede Getsemaní", "Calle de la Media Luna", "10-89", "Getsemaní", "Cartagena", "08:00", "20:00", False, "M"),
    ("Sede Manga", "Calle 26", "22-52", "Manga", "Cartagena", "07:30", "19:30", False, "P"),
    ("Sede Pinares", "Calle 14", "15-60", "Pinares", "Pereira", "07:00", "20:00", False, "P"),
    ("Sede Álamos", "Avenida Circunvalar", "9-44", "Álamos", "Pereira", "07:30", "19:30", False, "P"),
    ("Sede Palermo", "Carrera 23", "64-35", "Palermo", "Manizales", "07:00", "20:00", False, "P"),
    ("Sede Milán", "Calle 65A", "23B-30", "Milán", "Manizales", "07:30", "19:30", False, "P"),
    ("Sede El Rodadero", "Carrera 2", "6-41", "El Rodadero", "Santa Marta", "07:00", "20:00", False, "P"),
    ("Sede Caobos", "Avenida 1E", "13-56", "Caobos", "Cúcuta", "07:00", "19:00", False, "P"),
    ("Sede Cádiz", "Carrera 5", "37-50", "Cádiz", "Ibagué", "07:00", "19:00", False, "P"),
    ("Sede Barzal", "Calle 37", "38-12", "Barzal", "Villavicencio", "07:00", "19:00", False, "P"),
    ("Sede Las Cuadras", "Calle 20", "29-63", "Las Cuadras", "Pasto", "07:30", "19:30", False, "P"),
    ("Sede La Castellana", "Avenida Bolívar", "14N-39", "La Castellana", "Armenia", "07:30", "19:30", False, "P"),
    ("Sede Altico", "Carrera 7", "10-40", "Altico", "Neiva", "07:00", "19:00", False, "P"),
]

# Composición de espacios por tamaño de sede: lista de (tipo, cantidad mínima, cantidad máxima)
COMPOSICION = {
    "G": [(1, 2, 2), (2, 1, 2), (3, 1, 2), (4, 2, 2), (5, 0, 1), (6, 0, 1), (7, 1, 1)],
    "M": [(1, 1, 1), (2, 1, 1), (3, 1, 1), (4, 1, 1), (5, 0, 1), (7, 1, 1)],
    "P": [(1, 1, 1), (2, 1, 1), (4, 1, 1), (3, 0, 1), (7, 0, 1)],
}

NOMBRES_F = ["María", "Laura", "Valentina", "Daniela", "Camila", "Natalia", "Andrea", "Carolina",
             "Paula", "Juliana", "Sofía", "Catalina", "Diana", "Luisa", "Alejandra", "Tatiana",
             "Mónica", "Sara", "Manuela", "Ángela", "Lina", "Viviana", "Marcela", "Isabel"]
NOMBRES_M = ["Juan", "Andrés", "Carlos", "Santiago", "Felipe", "Sebastián", "David", "Alejandro",
             "Daniel", "Jorge", "Luis", "Camilo", "Diego", "Mateo", "Nicolás", "Julián", "Óscar",
             "Mauricio", "Esteban", "Ricardo", "Fernando", "Iván", "Hernán", "Simón"]
SEGUNDOS_F = ["José", "Fernanda", "Alejandra", "Paula", "Camila", "Isabel", "Lucía"]
SEGUNDOS_M = ["Pablo", "David", "José", "Felipe", "Andrés", "Esteban", "Manuel"]
APELLIDOS = ["Rodríguez", "Gómez", "González", "Martínez", "García", "López", "Hernández", "Sánchez",
             "Ramírez", "Pérez", "Díaz", "Muñoz", "Rojas", "Moreno", "Jiménez", "Vargas", "Castro",
             "Gutiérrez", "Ortiz", "Ospina", "Restrepo", "Cárdenas", "Valencia", "Quintero", "Mejía",
             "Arango", "Salazar", "Patiño", "Londoño", "Zapata", "Cortés", "Herrera", "Suárez",
             "Rincón", "Mendoza", "Peña", "Acosta", "Bermúdez", "Montoya", "Agudelo", "Cifuentes"]
DOMINIOS = ["gmail.com"] * 6 + ["hotmail.com"] * 2 + ["outlook.com"] * 2 + ["yahoo.es"]

PALABRA_EMPRESA = ["Andina", "Ceiba", "Nodo", "Cordillera", "Altiplano", "Guadua", "Cóndor",
                   "Orquídea", "Pacífico", "Caribe", "Sabana", "Páramo", "Yarumo", "Arrayán",
                   "Samán", "Magdalena", "Cauca", "Quindío", "Llanura", "Tequendama", "Nevado",
                   "Bahía", "Cafetal", "Manglar", "Frailejón", "Palmar", "Ébano", "Brújula",
                   "Faro", "Colibrí", "Zenú", "Muisca", "Atlántica", "Sierra", "Meridiano",
                   "Horizonte", "Vértice", "Cumbre", "Ruta", "Raíz", "Semilla", "Tejar",
                   "Puente", "Mirador", "Cuarzo", "Lumen", "Kumbia", "Aliso", "Balsa", "Ocelote"]
SECTOR_EMPRESA = ["Software", "Consultores", "Logística", "Digital", "Analítica", "Diseño",
                  "Ingeniería", "Marketing", "Abogados", "Contadores", "Energía", "Salud",
                  "Educación", "Fintech", "Agrotech", "Arquitectos", "Medios", "Tecnología"]
CONTACTO_ROL = ["contacto", "administracion", "gerencia", "compras", "reservas", "oficina"]

METODOS_NATURAL = ["Tarjeta de crédito"] * 4 + ["Tarjeta débito"] * 3 + ["Nequi"] * 3 + ["PSE"] * 2 + ["Efectivo"]
METODOS_EMPRESA = ["Transferencia"] * 5 + ["PSE"] * 3 + ["Tarjeta de crédito"] * 2

# ------------------------------------------------------------------
# Sedes, espacios y tarifas
# ------------------------------------------------------------------
sedes = []
for i, s in enumerate(SEDES, start=1):
    sedes.append(dict(id=i, nombre=s[0], calle=s[1], numero=s[2], barrio=s[3], ciudad=s[4],
                      apertura=t(s[5]), cierre=t(s[6]), premium=s[7], tam=s[8]))
SEDE = {s["id"]: s for s in sedes}

espacios = []
for s in sedes:
    lista = []
    for tipo_id, mn, mx in COMPOSICION[s["tam"]]:
        n = random.randint(mn, mx)
        if tipo_id == 6 and s["premium"] and s["tam"] == "G":
            n = 1  # las sedes premium grandes tienen auditorio
        for k in range(1, n + 1):
            cap = random.choice(TIPO[tipo_id][3])
            lista.append(dict(sede_id=s["id"], tipo_id=tipo_id, capacidad=cap,
                              codigo=f"{PREFIJO[tipo_id]}-{k:02d}"))
    espacios.extend(lista)

# La consulta de modificación que cambia capacidades actualiza la capacidad del espacio 18 a 10.
# Ese espacio debe ser una sala de reuniones para que el cambio tenga sentido.
idx18 = 17
if espacios[idx18]["tipo_id"] != 4:
    sede18 = espacios[idx18]["sede_id"]
    j = next(j for j, e in enumerate(espacios) if e["sede_id"] == sede18 and e["tipo_id"] == 4)
    espacios[idx18], espacios[j] = espacios[j], espacios[idx18]
espacios[idx18]["capacidad"] = 8

for i, e in enumerate(espacios, start=1):
    e["id"] = i
ESPACIO = {e["id"]: e for e in espacios}
espacios_por_sede = defaultdict(list)
for e in espacios:
    espacios_por_sede[e["sede_id"]].append(e)

tarifas = {}  # (sede, tipo, modalidad) -> valor
for s in sedes:
    mult = CIUDADES[s["ciudad"]][1] * (1.10 if s["premium"] else 1.0)
    for tipo_id in sorted({e["tipo_id"] for e in espacios_por_sede[s["id"]]}):
        base_h, base_d = TIPO[tipo_id][4], TIPO[tipo_id][5]
        jit = random.uniform(0.97, 1.03)
        tarifas[(s["id"], tipo_id, 1)] = redondear(base_h * mult * jit)
        if base_d is not None:
            tarifas[(s["id"], tipo_id, 2)] = redondear(base_d * mult * jit)

assert (2, 1, 2) in tarifas and (3, 2, 1) in tarifas  # usadas por las consultas de modificación

# ------------------------------------------------------------------
# Clientes
# ------------------------------------------------------------------
N_CLIENTES, N_NATURAL = 120, 70
N_DEFAULT = 3   # últimos clientes: fecha_registro toma el DEFAULT (fecha de carga)

tipos_cliente = ["NATURAL"] * N_NATURAL + ["EMPRESA"] * (N_CLIENTES - N_NATURAL)
random.shuffle(tipos_cliente)
# Los clientes con DEFAULT: dos naturales y una empresa
cola = tipos_cliente[:N_CLIENTES - N_DEFAULT]
nat_rest = N_NATURAL - cola.count("NATURAL")
emp_rest = (N_CLIENTES - N_NATURAL) - cola.count("EMPRESA")
while not (nat_rest == 2 and emp_rest == 1):
    random.shuffle(tipos_cliente)
    cola = tipos_cliente[:N_CLIENTES - N_DEFAULT]
    nat_rest = N_NATURAL - cola.count("NATURAL")
    emp_rest = (N_CLIENTES - N_NATURAL) - cola.count("EMPRESA")
tipos_cliente = cola + ["NATURAL", "NATURAL", "EMPRESA"]

# Fechas de registro crecientes con el id (los id siguen el orden de registro)
cupos = [(dt.date(2022, 1, 10), dt.date(2022, 11, 30), 35),
         (dt.date(2023, 1, 9), dt.date(2023, 12, 15), 25),
         (dt.date(2024, 1, 9), dt.date(2024, 12, 13), 25),
         (dt.date(2025, 1, 8), dt.date(2025, 12, 12), 20),
         (dt.date(2026, 1, 13), dt.date(2026, 10, 30), 12)]
fechas_registro = []
for ini, fin, n in cupos:
    dias = (fin - ini).days
    fechas_registro += sorted(ini + dt.timedelta(days=random.randint(0, dias)) for _ in range(n))
fechas_registro += [None] * N_DEFAULT

ciudades_peso = defaultdict(int)
for s in sedes:
    ciudades_peso[s["ciudad"]] += 1
CIUDAD_LISTA = list(ciudades_peso)
CIUDAD_PESO = [ciudades_peso[c] for c in CIUDAD_LISTA]

usados_email, usados_doc, usados_nit, usados_tel, usadas_razones = set(), set(), set(), set(), set()
usados_tel.add("3001234567")


def nuevo_movil():
    while True:
        pref = random.choice(["300", "301", "302", "304", "305", "310", "311", "312", "313", "314",
                              "315", "316", "317", "318", "319", "320", "321", "322", "323", "350", "351"])
        num = pref + f"{random.randint(0, 9_999_999):07d}"
        if num not in usados_tel:
            usados_tel.add(num)
            return num


def nuevo_fijo(ciudad):
    while True:
        num = CIUDADES[ciudad][0] + f"{random.randint(2_000_000, 7_999_999)}"
        if num not in usados_tel:
            usados_tel.add(num)
            return num


def dv_nit(base):
    pesos = [3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71]
    s = sum(int(d) * pesos[i] for i, d in enumerate(reversed(base)))
    r = s % 11
    return r if r < 2 else 11 - r


def nombre_persona(genero=None):
    genero = genero or random.choice("FM")
    if genero == "F":
        n = random.choice(NOMBRES_F)
        if random.random() < 0.3:
            n += " " + random.choice(SEGUNDOS_F)
    else:
        n = random.choice(NOMBRES_M)
        if random.random() < 0.3:
            n += " " + random.choice(SEGUNDOS_M)
    a1, a2 = random.sample(APELLIDOS, 2)
    nombre_persona.genero = genero
    return n, f"{a1} {a2}"


clientes = []
for cid in range(1, N_CLIENTES + 1):
    tipo = tipos_cliente[cid - 1]
    freg = fechas_registro[cid - 1]
    ciudad = random.choices(CIUDAD_LISTA, CIUDAD_PESO)[0]
    c = dict(id=cid, tipo=tipo, fecha_registro=freg, ciudad=ciudad, telefonos=[])
    if tipo == "NATURAL":
        nombres, apellidos = nombre_persona()
        ref = freg or HOY
        edad = random.randint(19, 58)
        nac = dt.date(ref.year - edad, random.randint(1, 12), random.randint(1, 28))
        if nac.year < 1988:
            while True:
                prefijos = [52, 51, 43, 39] if nombre_persona.genero == "F" else [79, 80, 71, 70]
                doc = str(random.choice(prefijos)) + f"{random.randint(0, 999_999):06d}"
                if doc not in usados_doc:
                    break
        else:
            while True:
                doc = "10" + f"{random.randint(0, 99_999_999):08d}"
                if doc not in usados_doc:
                    break
        usados_doc.add(doc)
        base = f"{ascii_slug(nombres.split()[0])}.{ascii_slug(apellidos.split()[0])}"
        email = f"{base}@{random.choice(DOMINIOS)}"
        k = 0
        while email in usados_email:
            k += 1
            email = f"{base}{nac.year % 100:02d}{'' if k == 1 else k}@{random.choice(DOMINIOS)}"
        c.update(documento=doc, nombres=nombres, apellidos=apellidos, nacimiento=nac)
        c["telefonos"].append(nuevo_movil())
        if random.random() < 0.2:
            c["telefonos"].append(nuevo_movil())
        c["peso"] = min(random.paretovariate(1.6), 5)
    else:
        while True:
            razon = f"{random.choice(PALABRA_EMPRESA)} {random.choice(SECTOR_EMPRESA)}"
            if razon not in usadas_razones:
                break
        usadas_razones.add(razon)
        sufijo = random.choices(["S.A.S.", "Ltda.", "S.A."], [8, 1, 1])[0]
        anio = (freg or HOY).year
        while True:
            pref = random.choice(["800", "830", "860"]) if random.random() < 0.3 else random.choice(["900", "901"])
            base = pref + f"{random.randint(0, 999_999):06d}"
            if base not in usados_nit:
                break
        usados_nit.add(base)
        nit = f"{base}-{dv_nit(base)}"
        cn, ca = nombre_persona()
        slug = ascii_slug(razon.replace(" ", ""))
        email = f"{random.choice(CONTACTO_ROL)}@{slug}.com.co"
        c.update(nit=nit, razon=f"{razon} {sufijo}", contacto=f"{cn} {ca}")
        c["telefonos"].append(nuevo_fijo(ciudad))
        if random.random() < 0.7:
            c["telefonos"].append(nuevo_movil())
        c["peso"] = min(random.paretovariate(1.6), 5) * 1.5
    usados_email.add(email)
    c["email"] = email
    clientes.append(c)

# La consulta de modificación que borra teléfonos quita el teléfono 3001234567 del cliente 15.
# El cliente 15 queda con ese número y otro más, para que no se quede sin teléfono.
c15 = clientes[14]
c15["telefonos"] = ["3001234567"] + [x for x in c15["telefonos"] if x.startswith("3")][:1]
if len(c15["telefonos"]) < 2:
    c15["telefonos"].append(nuevo_movil())

CLIENTE = {c["id"]: c for c in clientes}

# ------------------------------------------------------------------
# Reservas
# ------------------------------------------------------------------
ocupacion = defaultdict(list)  # espacio_id -> [(inicio, fin)]


def libre(eid, ini, fin):
    return all(fin <= a or ini >= b for a, b in ocupacion[eid])


def elegir_tipos(cliente):
    if cliente["tipo"] == "NATURAL":
        tipos = random.choices([1, 2, 7, 4, 3, 5], [35, 25, 15, 15, 7, 3])[0:1]
        if random.random() < 0.05:
            tipos.append(7 if tipos[0] != 7 else 1)
        return tipos
    n = random.choices([1, 2, 3], [60, 30, 10])[0]
    principal = random.choices([4, 3, 5, 6, 2, 1], [35, 25, 12, 8, 10, 10])[0]
    tipos = [principal]
    while len(tipos) < n:
        tipos.append(random.choice([1, 2, 3, 4, 7]))
    return tipos


def elegir_modalidad(tipo_id):
    if tipo_id == 7:
        return 1
    if tipo_id in (1, 2, 3):
        return random.choices([1, 2], [45, 55])[0]
    if tipo_id == 4:
        return random.choices([1, 2], [85, 15])[0]
    return random.choices([1, 2], [60, 40])[0]


def anticipacion(cliente, tipo_id):
    if tipo_id in (5, 6):
        return random.randint(7, 45)
    if cliente["tipo"] == "EMPRESA":
        return random.randint(1, 25)
    return min(int(random.expovariate(1 / 3)), 14)


def ventana(sede, fecha, modalidad, tipo_id, cliente):
    ap = dt.datetime.combine(fecha, sede["apertura"])
    ci = dt.datetime.combine(fecha, sede["cierre"])
    if modalidad == 2:
        return ap, ci
    if tipo_id in (5, 6):
        dur = random.choice([3, 4, 5, 6])
    elif tipo_id == 4:
        dur = random.choice([1, 1.5, 2, 2, 3, 4])
    elif tipo_id == 7:
        dur = random.choice([1, 1, 2])
    else:
        dur = random.choice([1, 2, 3, 4, 4])
    dur_min = int(dur * 60)
    ultimo = int((ci - ap).total_seconds() // 60) - dur_min
    # preferencia por horas de oficina
    inicio_min = random.choice(range(0, ultimo + 1, 30))
    if random.random() < 0.7:
        inicio_min = random.choice(range(max(0, 60), min(ultimo, 9 * 60) + 1, 30))
    ini = ap + dt.timedelta(minutes=inicio_min)
    return ini, ini + dt.timedelta(minutes=dur_min)


def candidatos(cliente, fecha):
    return [c for c in clientes if c["fecha_registro"] is not None and c["fecha_registro"] <= fecha]


def unidades(ini, fin, modalidad):
    return 1 if modalidad == 2 else (fin - ini).total_seconds() / 3600


reservas = []


def crear_reserva(fecha_creacion, cliente, sede, tipos, modalidad=None, fecha_uso=None, hora=None):
    if modalidad is None:
        modalidad = elegir_modalidad(tipos[0])
    if modalidad == 2:
        tipos = [x for x in tipos if (sede["id"], x, 2) in tarifas]
    tipos = [x for x in tipos if any(e["tipo_id"] == x for e in espacios_por_sede[sede["id"]])]
    if not tipos:
        return None
    for intento in range(30):
        fecha = fecha_uso or no_domingo(fecha_creacion + dt.timedelta(days=anticipacion(cliente, tipos[0]) + intento // 6))
        if hora:
            ini, fin = hora
        else:
            ini, fin = ventana(sede, fecha, modalidad, tipos[0], cliente)
        if ini.date() < fecha_creacion or (ini.date() == fecha_creacion and fecha_creacion == HOY):
            continue
        elegidos = []
        for x in tipos:
            opciones = [e for e in espacios_por_sede[sede["id"]]
                        if e["tipo_id"] == x and e not in elegidos and libre(e["id"], ini, fin)]
            if opciones:
                elegidos.append(random.choice(opciones))
        if len(elegidos) == len(tipos):
            for e in elegidos:
                ocupacion[e["id"]].append((ini, fin))
            r = dict(fecha_creacion=fecha_creacion, cliente=cliente, sede=sede, modalidad=modalidad,
                     inicio=ini, fin=fin,
                     lineas=[dict(espacio=e, tarifa=tarifas[(sede["id"], e["tipo_id"], modalidad)])
                             for e in elegidos])
            return r
    return None


# Reserva especial para la consulta que retira un espacio de una reserva: confirmada, futura, con el espacio 12 y otro espacio
e12 = ESPACIO[12]
sede12 = SEDE[e12["sede_id"]]
otro = next(e for e in espacios_por_sede[sede12["id"]] if e["id"] != 12 and e["tipo_id"] in (3, 4) and e["tipo_id"] != e12["tipo_id"])
empresa_c8 = next(c for c in clientes if c["tipo"] == "EMPRESA" and c["ciudad"] == sede12["ciudad"]
                  and c["fecha_registro"] is not None)
ini8 = dt.datetime(2026, 11, 26, 9, 0)
fin8 = dt.datetime(2026, 11, 26, 13, 0)
especial_c8 = dict(fecha_creacion=dt.date(2026, 11, 9), cliente=empresa_c8, sede=sede12, modalidad=1,
                   inicio=ini8, fin=fin8, estado="CONFIRMADA",
                   lineas=[dict(espacio=e12, tarifa=tarifas[(sede12["id"], e12["tipo_id"], 1)]),
                           dict(espacio=otro, tarifa=tarifas[(sede12["id"], otro["tipo_id"], 1)])])
for ln in especial_c8["lineas"]:
    ocupacion[ln["espacio"]["id"]].append((ini8, fin8))
reservas.append(especial_c8)

# Fechas de creación: más densas hacia el final (la red crece).
# Las últimas tres semanas tienen su propio grupo para que haya reservas futuras.
N_RESERVAS = 200
N_RECIENTES = 40
CORTE_RECIENTES = dt.date(2026, 10, 26)
dias_hist = (CORTE_RECIENTES - INICIO_DATOS).days
dias_rec = (HOY - CORTE_RECIENTES).days


def fecha_historica():
    return no_domingo(INICIO_DATOS + dt.timedelta(days=int(dias_hist * random.random() ** 0.75)))


def fecha_reciente():
    f = no_domingo(CORTE_RECIENTES + dt.timedelta(days=random.randint(0, dias_rec - 1)))
    return f if f < HOY else HOY - dt.timedelta(days=1)


def intentar(fc, reciente):
    cands = candidatos(None, fc)
    cliente = random.choices(cands, [c["peso"] for c in cands])[0]
    if random.random() < 0.85:
        sede = random.choice([s for s in sedes if s["ciudad"] == cliente["ciudad"]])
    else:
        sede = random.choice(sedes)
    tipos = elegir_tipos(cliente)
    if not any(e["tipo_id"] == tipos[0] for e in espacios_por_sede[sede["id"]]):
        con_tipo = [x for x in sedes if x["ciudad"] == sede["ciudad"]
                    and any(e["tipo_id"] == tipos[0] for e in espacios_por_sede[x["id"]])]
        if con_tipo:
            sede = random.choice(con_tipo)
    fecha_uso = None
    if reciente and random.random() < 0.75:
        fecha_uso = no_domingo(HOY + dt.timedelta(days=random.randint(0, 24)))
    return crear_reserva(fc, cliente, sede, tipos, fecha_uso=fecha_uso)


n_hist = N_RESERVAS - len(reservas) - N_RECIENTES
for grupo, n, gen in ((False, n_hist, fecha_historica), (True, N_RECIENTES, fecha_reciente)):
    hechas = 0
    while hechas < n:
        r = intentar(gen(), grupo)
        if r:
            reservas.append(r)
            hechas += 1

reservas.sort(key=lambda r: (r["fecha_creacion"], r["inicio"]))

# Estados según fechas
for r in reservas:
    if "estado" in r:
        continue
    if r["fin"].date() < HOY:
        r["estado"] = random.choices(["FINALIZADA", "CANCELADA"], [87, 13])[0]
    elif (HOY - r["fecha_creacion"]).days <= 3:
        r["estado"] = random.choices(["PENDIENTE", "CONFIRMADA", "CANCELADA"], [55, 40, 5])[0]
    else:
        r["estado"] = random.choices(["CONFIRMADA", "PENDIENTE", "CANCELADA"], [70, 20, 10])[0]

for i, r in enumerate(reservas, start=1):
    r["id"] = i
    r["total"] = int(round(sum(ln["tarifa"] * unidades(r["inicio"], r["fin"], r["modalidad"])
                               for ln in r["lineas"])))

# ------------------------------------------------------------------
# Cuotas
# ------------------------------------------------------------------
def partir(total, n):
    base = int(total / n / 100) * 100
    partes = [base] * (n - 1)
    partes.append(total - base * (n - 1))
    return partes


cuotas = []
for r in reservas:
    total = r["total"]
    emp = r["cliente"]["tipo"] == "EMPRESA"
    if total < 200_000:
        n = 1
    elif total < 1_000_000:
        n = random.choices([1, 2], [60, 40])[0]
    else:
        n = random.choices([2, 3], [50, 50])[0]
    metodos = METODOS_EMPRESA if emp else METODOS_NATURAL
    fc, fu = r["fecha_creacion"], r["inicio"].date()
    est = r["estado"]
    if est == "FINALIZADA":
        partes = partir(total, n)
        limite = min(fu + dt.timedelta(days=20 if emp else 0), HOY - dt.timedelta(days=1))
        fechas = sorted(fc + dt.timedelta(days=random.randint(0, max(0, (limite - fc).days))) for _ in range(n))
        fechas[0] = min(fechas[0], fc + dt.timedelta(days=2), limite)
        fechas = sorted(fechas)
        metodo = random.choice(metodos)
        for k, (m, f) in enumerate(zip(partes, fechas), start=1):
            cuotas.append((r["id"], k, m, f, metodo))
    elif est == "CONFIRMADA":
        partes = partir(total, n)
        f1 = min(fc + dt.timedelta(days=random.randint(0, 1)), HOY)
        metodo = random.choice(metodos)
        for k, m in enumerate(partes, start=1):
            if k == 1:
                cuotas.append((r["id"], k, m, f1, metodo))
            else:
                cuotas.append((r["id"], k, m, None, None))
    elif est == "PENDIENTE":
        if random.random() < 0.7:
            for k, m in enumerate(partir(total, n), start=1):
                cuotas.append((r["id"], k, m, None, None))
    else:  # CANCELADA
        if random.random() < 0.3:
            for k, m in enumerate(partir(total, n), start=1):
                cuotas.append((r["id"], k, m, None, None))

# ------------------------------------------------------------------
# Salida SQL
# ------------------------------------------------------------------
out = []
w = out.append


def bloque(tabla, columnas, filas, por_lote=50):
    for i in range(0, len(filas), por_lote):
        lote = filas[i:i + por_lote]
        w(f"INSERT INTO {tabla} ({', '.join(columnas)}) VALUES")
        w(",\n".join("    (" + ", ".join(v(x) for x in f) + ")" for f in lote) + ";")
        w("")


conteo = {}
reservas_esp = [(r["id"], ln["espacio"]["id"], r["inicio"], r["fin"], ln["tarifa"])
                for r in reservas for ln in r["lineas"]]
conteo = dict(sede=len(sedes), tipo_espacio=len(TIPOS), modalidad=len(MODALIDADES),
              espacio=len(espacios), tarifa=len(tarifas), cliente=len(clientes),
              persona_natural=sum(c["tipo"] == "NATURAL" for c in clientes),
              empresa=sum(c["tipo"] == "EMPRESA" for c in clientes),
              telefono_cliente=sum(len(c["telefonos"]) for c in clientes),
              reserva=len(reservas), reserva_espacio=len(reservas_esp), cuota=len(cuotas))

pend_c4 = [r for r in reservas if r["estado"] == "PENDIENTE" and r["inicio"].date() >= HOY]
id_c4 = pend_c4[0]["id"] if pend_c4 else None
id_c8 = especial_c8["id"]
otro_c8 = otro["id"]

w("-- ============================================================")
w("-- DATOS DE PRUEBA")
w("-- Caso 6: Red de espacios de coworking")
w("-- ============================================================")
w("--")
w("-- Orden de ejecución: 01_ddl.sql, 02_datos_prueba.sql,")
w("-- 02_verificacion_datos.sql, 03_consultas.sql, 04_datos_sinteticos.sql,")
w("-- 05_indices.sql y 06_consultas_analisis.sql.")
w("-- Fecha de corte de los datos: 2026-11-16. Las reservas anteriores a esa")
w("-- fecha están FINALIZADAS o CANCELADAS; las posteriores, CONFIRMADAS,")
w("-- PENDIENTES o CANCELADAS.")
w("--")
w("-- Filas por tabla:")
for k, n in conteo.items():
    w(f"--   {k:<18} {n:>4}")
w("--")
w("-- modalidad y tipo_espacio son catálogos y no llegan a 50 filas:")
w("--   modalidad solo admite 'Hora' y 'Dia' (CHECK ck_modalidad_nombre).")
w("--   tipo_espacio tiene los 7 tipos que ofrece la red; inventar 50 tipos")
w("--   haría los datos menos realistas, no más.")
w("--")
w("-- Reglas que cumplen los datos, aunque el DDL todavía no las obliga:")
w("--   - Cada cliente está en una sola subclase y coincide con tipo_cliente.")
w("--   - Un espacio nunca tiene dos reservas que se crucen en el tiempo.")
w("--   - Toda reserva cae dentro del horario de su sede. Las reservas por")
w("--     día van de la apertura al cierre.")
w("--   - Todos los espacios de una reserva son de la misma sede.")
w("--   - tarifa_aplicada es el valor por hora o por día de la tabla tarifa")
w("--     al momento de reservar. Valor de una línea = tarifa_aplicada x")
w("--     horas (modalidad Hora) o x 1 (modalidad Dia).")
w("--   - Las cabinas telefónicas solo se alquilan por hora.")
w("--   - fecha_registro <= fecha_creacion <= fecha del uso.")
w("--   - En reservas FINALIZADAS todas las cuotas están pagadas y suman el")
w("--     valor de la reserva. En las CONFIRMADAS la cuota 1 está pagada.")
w("--     Las PENDIENTES y CANCELADAS no tienen cuotas pagadas.")
w("--")
w("-- Filas que usan las consultas de modificación:")
w("--   Confirmar una reserva: la reserva %d está PENDIENTE." % id_c4)
w("--   Actualizar una tarifa: existe (sede 2, tipo 1, modalidad 2 = Dia).")
w("--   Cambiar capacidad: el espacio 18 es una sala de reuniones de 8.")
w("--   Borrar un teléfono: el cliente 15 tiene el 3001234567 y otro más.")
w("--   Retirar un espacio: la reserva %d está CONFIRMADA con los" % id_c8)
w("--       espacios 12 y %d." % otro_c8)
w("--   Eliminar una tarifa: existe (sede 3, tipo 2, modalidad 1 = Hora).")
w("-- ============================================================")
w("")
w("SET NAMES utf8mb4;")
w("USE coworking_db;")
w("")
w("START TRANSACTION;")
w("")

w("-- ------------------------------------------------------------")
w("-- MODALIDAD (catálogo)")
w("-- ------------------------------------------------------------")
bloque("modalidad", ["modalidad_id", "nombre"], MODALIDADES)

w("-- ------------------------------------------------------------")
w("-- TIPO_ESPACIO (catálogo)")
w("-- ------------------------------------------------------------")
bloque("tipo_espacio", ["tipo_id", "nombre", "descripcion"], [(x[0], x[1], x[2]) for x in TIPOS])

w("-- ------------------------------------------------------------")
w(f"-- SEDE ({len(sedes)} sedes en {len(CIUDADES)} ciudades)")
w("-- ------------------------------------------------------------")
bloque("sede", ["sede_id", "nombre", "calle", "numero", "barrio", "ciudad", "hora_apertura", "hora_cierre"],
       [(s["id"], s["nombre"], s["calle"], s["numero"], s["barrio"], s["ciudad"], s["apertura"], s["cierre"])
        for s in sedes])

w("-- ------------------------------------------------------------")
w("-- ESPACIO")
w("-- Código: EF escritorio flexible, ED escritorio dedicado,")
w("-- OF oficina, SR sala de reuniones, SC sala de capacitación,")
w("-- AUD auditorio, CB cabina telefónica.")
w("-- ------------------------------------------------------------")
bloque("espacio", ["espacio_id", "codigo", "capacidad", "sede_id", "tipo_id"],
       [(e["id"], e["codigo"], e["capacidad"], e["sede_id"], e["tipo_id"]) for e in espacios])

w("-- ------------------------------------------------------------")
w("-- TARIFA (pesos colombianos)")
w("-- Precio base de Bogotá ajustado por ciudad; las sedes de zonas")
w("-- de mayor demanda cobran 10 % más.")
w("-- ------------------------------------------------------------")
bloque("tarifa", ["sede_id", "tipo_id", "modalidad_id", "valor"],
       [(k[0], k[1], k[2], val) for k, val in sorted(tarifas.items())])

w("-- ------------------------------------------------------------")
w("-- CLIENTE")
w("-- Los id siguen el orden de registro.")
w("-- ------------------------------------------------------------")
bloque("cliente", ["cliente_id", "email", "fecha_registro", "tipo_cliente"],
       [(c["id"], c["email"], c["fecha_registro"], c["tipo"]) for c in clientes if c["fecha_registro"]])
w("-- Clientes registrados el día de la carga: fecha_registro toma el DEFAULT.")
w("-- No tienen reservas.")
bloque("cliente", ["cliente_id", "email", "tipo_cliente"],
       [(c["id"], c["email"], c["tipo"]) for c in clientes if not c["fecha_registro"]])

w("-- ------------------------------------------------------------")
w("-- PERSONA_NATURAL")
w("-- ------------------------------------------------------------")
bloque("persona_natural", ["cliente_id", "documento", "nombres", "apellidos", "fecha_nacimiento"],
       [(c["id"], c["documento"], c["nombres"], c["apellidos"], c["nacimiento"])
        for c in clientes if c["tipo"] == "NATURAL"])

w("-- ------------------------------------------------------------")
w("-- EMPRESA (NIT con dígito de verificación calculado como la DIAN)")
w("-- ------------------------------------------------------------")
bloque("empresa", ["cliente_id", "nit", "razon_social", "nombre_contacto"],
       [(c["id"], c["nit"], c["razon"], c["contacto"]) for c in clientes if c["tipo"] == "EMPRESA"])

w("-- ------------------------------------------------------------")
w("-- TELEFONO_CLIENTE")
w("-- ------------------------------------------------------------")
bloque("telefono_cliente", ["cliente_id", "telefono"],
       [(c["id"], tel) for c in clientes for tel in c["telefonos"]], por_lote=60)

w("-- ------------------------------------------------------------")
w("-- RESERVA")
w("-- ------------------------------------------------------------")
bloque("reserva", ["reserva_id", "fecha_creacion", "estado", "cliente_id", "modalidad_id"],
       [(r["id"], r["fecha_creacion"], r["estado"], r["cliente"]["id"], r["modalidad"]) for r in reservas])

w("-- ------------------------------------------------------------")
w("-- RESERVA_ESPACIO")
w("-- ------------------------------------------------------------")
bloque("reserva_espacio", ["reserva_id", "espacio_id", "inicio", "fin", "tarifa_aplicada"], reservas_esp)

w("-- ------------------------------------------------------------")
w("-- CUOTA")
w("-- fecha_pago y metodo_pago en NULL = cuota sin pagar.")
w("-- ------------------------------------------------------------")
bloque("cuota", ["reserva_id", "num_cuota", "monto", "fecha_pago", "metodo_pago"], cuotas)

w("COMMIT;")
w("")

print("\n".join(out))

import sys
print(f"-- conteo: {conteo}  C4={id_c4}  C8={id_c8} (espacios 12 y {otro_c8})", file=sys.stderr)
