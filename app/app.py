"""Aplicación web de la red de coworking.

Para ejecutarla (ver README): python app/app.py
y abrir http://127.0.0.1:5000 en el navegador.

Cada página sigue el mismo patrón:
  1. lee el formulario;
  2. lo valida con validaciones.py (si hay errores, los muestra y no
     toca la base de datos);
  3. llama un procedimiento almacenado con db.llamar();
  4. muestra el resultado o el mensaje de error de la base de datos.
"""

import os

from flask import Flask, flash, redirect, render_template, request, url_for

import validaciones as v
from db import ErrorBD, llamar

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "clave-solo-para-desarrollo")

ESTADOS = ["PENDIENTE", "CONFIRMADA", "CANCELADA", "FINALIZADA"]


@app.template_filter("dinero")
def dinero(valor):
    """1234567.5 -> $1.234.568 (vacío si no hay valor)."""
    if valor is None:
        return ""
    return "$" + f"{float(valor):,.0f}".replace(",", ".")


@app.template_filter("hora")
def hora(valor):
    """MySQL entrega los TIME como timedelta; se muestran como HH:MM."""
    if valor is None:
        return ""
    minutos = int(valor.total_seconds()) // 60
    return f"{minutos // 60:02d}:{minutos % 60:02d}"


def catalogos():
    """Modalidades, tipos de espacio y ciudades para los formularios."""
    tablas, _ = llamar("sp_app_listar_catalogos")
    modalidades, tipos, ciudades = tablas
    return modalidades, tipos, [c["ciudad"] for c in ciudades]


def mostrar_errores(errores):
    for error in errores:
        flash(error, "error")


@app.errorhandler(ErrorBD)
def error_de_base_de_datos(error):
    """Si una consulta de solo lectura falla, se muestra en la página de inicio."""
    flash(str(error), "error")
    return render_template("inicio.html"), 500


@app.route("/")
def inicio():
    return render_template("inicio.html")


# ------------------------------------------------------------
# Espacios (solo consulta)
# ------------------------------------------------------------

@app.route("/espacios")
def espacios():
    _, tipos, ciudades = catalogos()
    ciudad = request.args.get("ciudad") or None
    try:
        tipo_id = v.entero_opcional(request.args.get("tipo_id"))
    except ValueError:
        tipo_id = None
    tablas, _ = llamar("sp_app_listar_espacios", ciudad, tipo_id)
    return render_template("espacios.html", espacios=tablas[0], ciudades=ciudades,
                           tipos=tipos, ciudad=ciudad, tipo_id=tipo_id)


# ------------------------------------------------------------
# Clientes
# ------------------------------------------------------------

@app.route("/clientes")
def clientes():
    buscar = request.args.get("buscar", "").strip()
    tablas, _ = llamar("sp_app_listar_clientes", buscar)
    return render_template("clientes.html", clientes=tablas[0], buscar=buscar)


@app.route("/clientes/nuevo", methods=["GET", "POST"])
def cliente_nuevo():
    datos = request.form
    if request.method == "POST":
        errores = v.validar_cliente(datos)
        if errores:
            mostrar_errores(errores)
        else:
            natural = datos["tipo_cliente"] == "NATURAL"
            try:
                _, salida = llamar(
                    "sp_app_registrar_cliente",
                    datos["tipo_cliente"], v.texto(datos, "email"), v.texto(datos, "telefono"),
                    v.texto(datos, "documento") if natural else None,
                    v.texto(datos, "nombres") if natural else None,
                    v.texto(datos, "apellidos") if natural else None,
                    v.texto(datos, "fecha_nacimiento") if natural else None,
                    None if natural else v.texto(datos, "nit"),
                    None if natural else v.texto(datos, "razon_social"),
                    None if natural else v.texto(datos, "nombre_contacto"),
                    None,  # OUT p_cliente_id
                )
                cliente_id = salida[-1]
                flash(f"Cliente {cliente_id} registrado.", "ok")
                return redirect(url_for("cliente_detalle", cliente_id=cliente_id))
            except ErrorBD as error:
                flash(str(error), "error")
    return render_template("cliente_nuevo.html", datos=datos)


@app.route("/clientes/<int:cliente_id>")
def cliente_detalle(cliente_id):
    try:
        tablas, _ = llamar("sp_app_obtener_cliente", cliente_id)
    except ErrorBD as error:
        flash(str(error), "error")
        return redirect(url_for("clientes"))
    cliente, telefonos = tablas[0][0], [t["telefono"] for t in tablas[1]]
    reservas, _ = llamar("sp_app_listar_reservas", None, cliente_id)
    return render_template("cliente_detalle.html", cliente=cliente,
                           telefonos=telefonos, reservas=reservas[0])


@app.route("/clientes/<int:cliente_id>/editar", methods=["POST"])
def cliente_editar(cliente_id):
    datos = request.form
    errores = v.validar_edicion_cliente(datos, datos.get("tipo_cliente"))
    if errores:
        mostrar_errores(errores)
    else:
        try:
            llamar("sp_app_actualizar_cliente", cliente_id,
                   v.texto(datos, "email"),
                   v.texto(datos, "nombres") or None, v.texto(datos, "apellidos") or None,
                   v.texto(datos, "razon_social") or None, v.texto(datos, "nombre_contacto") or None,
                   v.texto(datos, "telefono_nuevo") or None)
            flash("Datos del cliente actualizados.", "ok")
        except ErrorBD as error:
            flash(str(error), "error")
    return redirect(url_for("cliente_detalle", cliente_id=cliente_id))


@app.route("/clientes/<int:cliente_id>/eliminar", methods=["POST"])
def cliente_eliminar(cliente_id):
    try:
        llamar("sp_app_eliminar_cliente", cliente_id)
        flash(f"Cliente {cliente_id} eliminado.", "ok")
        return redirect(url_for("clientes"))
    except ErrorBD as error:
        flash(str(error), "error")
        return redirect(url_for("cliente_detalle", cliente_id=cliente_id))


# ------------------------------------------------------------
# Reservas
# ------------------------------------------------------------

@app.route("/reservas")
def reservas():
    estado = request.args.get("estado") or None
    tablas, _ = llamar("sp_app_listar_reservas", estado, None)
    return render_template("reservas.html", reservas=tablas[0], estados=ESTADOS, estado=estado)


@app.route("/reservas/nueva", methods=["GET", "POST"])
def reserva_nueva():
    modalidades, _, ciudades = catalogos()
    datos = request.values
    # Primero se elige la ciudad; con ella se llenan las listas de espacios.
    ciudad = datos.get("ciudad") or None
    lista_espacios = llamar("sp_app_listar_espacios", ciudad, None)[0][0] if ciudad else []
    lista_clientes = llamar("sp_app_listar_clientes", "")[0][0]

    if request.method == "POST":
        nombres = {str(m["modalidad_id"]): m["nombre"] for m in modalidades}
        modalidad = nombres.get(datos.get("modalidad_id"), "")
        errores = v.validar_reserva(datos, modalidad)
        if errores:
            mostrar_errores(errores)
        else:
            por_hora = modalidad == "Hora"
            try:
                _, salida = llamar(
                    "sp_app_crear_reserva",
                    int(datos["cliente_id"]), int(datos["modalidad_id"]), v.texto(datos, "fecha"),
                    v.texto(datos, "hora_inicio") if por_hora else None,
                    v.texto(datos, "hora_fin") if por_hora else None,
                    v.entero_opcional(datos.get("espacio_1")),
                    v.entero_opcional(datos.get("espacio_2")),
                    v.entero_opcional(datos.get("espacio_3")),
                    float(v.texto(datos, "anticipo") or 0),
                    v.texto(datos, "metodo_pago") or None,
                    None,  # OUT p_reserva_id
                )
                reserva_id = salida[-1]
                flash(f"Reserva {reserva_id} creada.", "ok")
                return redirect(url_for("reserva_detalle", reserva_id=reserva_id))
            except ErrorBD as error:
                flash(str(error), "error")

    return render_template("reserva_nueva.html", datos=datos, ciudad=ciudad, ciudades=ciudades,
                           modalidades=modalidades, espacios=lista_espacios,
                           clientes=lista_clientes, metodos=v.METODOS_PAGO)


@app.route("/reservas/<int:reserva_id>")
def reserva_detalle(reserva_id):
    try:
        tablas, _ = llamar("sp_app_detalle_reserva", reserva_id)
    except ErrorBD as error:
        flash(str(error), "error")
        return redirect(url_for("reservas"))
    resumen, espacios_reserva, cuotas = tablas[0][0], tablas[1], tablas[2]
    return render_template("reserva_detalle.html", r=resumen, espacios=espacios_reserva,
                           cuotas=cuotas, metodos=v.METODOS_PAGO)


@app.route("/reservas/<int:reserva_id>/pagar", methods=["POST"])
def reserva_pagar(reserva_id):
    metodo = request.form.get("metodo_pago", "")
    if metodo not in v.METODOS_PAGO:
        flash("Seleccione el método de pago.", "error")
    else:
        try:
            llamar("sp_app_pagar_cuota", reserva_id, int(request.form["num_cuota"]), metodo)
            flash("Pago registrado.", "ok")
        except ErrorBD as error:
            flash(str(error), "error")
    return redirect(url_for("reserva_detalle", reserva_id=reserva_id))


@app.route("/reservas/<int:reserva_id>/estado", methods=["POST"])
def reserva_estado(reserva_id):
    nuevo = request.form.get("estado", "")
    try:
        llamar("sp_app_cambiar_estado", reserva_id, nuevo)
        flash(f"La reserva quedó {nuevo}.", "ok")
    except ErrorBD as error:
        flash(str(error), "error")
    return redirect(url_for("reserva_detalle", reserva_id=reserva_id))


@app.route("/reservas/<int:reserva_id>/eliminar", methods=["POST"])
def reserva_eliminar(reserva_id):
    try:
        llamar("sp_app_eliminar_reserva", reserva_id)
        flash(f"Reserva {reserva_id} eliminada.", "ok")
        return redirect(url_for("reservas"))
    except ErrorBD as error:
        flash(str(error), "error")
        return redirect(url_for("reserva_detalle", reserva_id=reserva_id))


if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_DEBUG") == "1")
