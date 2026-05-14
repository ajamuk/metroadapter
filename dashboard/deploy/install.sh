#!/usr/bin/env bash
# install.sh — CrossFit MPO Dashboard self-contained installer
set -e

APP_DIR="/opt/crossfitmpo-dashboard"
LOG_DIR="/var/log/crossfitmpo-dashboard"
SERVICE_NAME="crossfitmpo-dashboard"
DOMAIN="dashboard.crossfitmpo.com"

# ── 1. System dependencies ───────────────────────────────────────────────────
echo "=== Installing system dependencies ==="
apt-get update -q
apt-get install -y python3 python3-venv nginx certbot python3-certbot-nginx curl

# ── 2. Directory structure ───────────────────────────────────────────────────
echo "=== Creating directory structure ==="
mkdir -p \
  "${APP_DIR}/templates" \
  "${APP_DIR}/static/css" \
  "${APP_DIR}/static/js" \
  "${APP_DIR}/static/vendor/fonts" \
  "${LOG_DIR}"

# ── 3. Write source files ────────────────────────────────────────────────────
echo "=== Writing source files ==="

cat > "${APP_DIR}/requirements.txt" << 'EOF'
flask>=3.0
gunicorn>=21.2
requests>=2.31
EOF

cat > "${APP_DIR}/wsgi.py" << 'EOF'
from app import app

if __name__ == "__main__":
    app.run()
EOF

cat > "${APP_DIR}/config.py" << 'EOF'
import os, secrets

SHEET_ID = "1FnRLNy8LMj1kwkH7N3v0vEC-Cp0dI4n9JT1b0mdByj4"
USERNAME = "Carlos"
# werkzeug hash of "invictus2017"
PASSWORD_HASH = "scrypt:32768:8:1$eVm5XImrKFc71Yys$3b70c16b3e99c6a56a5b12048f10236c4b028d80c4e57999601a2be6ee2ea85f6740fe01671ee8356b3fce995e727534a9eb92a57e4483027fab253ab301ff4b"
SECRET_KEY = os.environ.get("SECRET_KEY", "cXmpo-dashboard-secret-2025-xK9pLmN3qR7tWvZ1")
CACHE_TTL = 600  # segundos
EOF

cat > "${APP_DIR}/app.py" << 'EOF'
from functools import wraps

from flask import Flask, jsonify, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash

import config
import sheets

app = Flask(__name__)
app.secret_key = config.SECRET_KEY
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("logged_in"):
        return redirect(url_for("dashboard"))
    error = None
    if request.method == "POST":
        user = request.form.get("username", "").strip()
        pwd = request.form.get("password", "")
        if user == config.USERNAME and check_password_hash(config.PASSWORD_HASH, pwd):
            session["logged_in"] = True
            session["username"] = user
            return redirect(url_for("dashboard"))
        error = "Usuario o contraseña incorrectos"
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/")
@login_required
def dashboard():
    return render_template("simple.html")


@app.route("/detalle")
@login_required
def detalle():
    return render_template("full.html")


@app.route("/api/data")
@login_required
def api_data():
    try:
        data = sheets.get_all_data()
        return jsonify({"ok": True, "data": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/refresh", methods=["POST"])
@login_required
def api_refresh():
    sheets.invalidate_cache()
    return jsonify({"ok": True})


if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=5000)
EOF

cat > "${APP_DIR}/sheets.py" << 'EOF'
"""
Fetches and parses data from the public Google Sheet.

CUADRO MANDOS sheet structure (106 CSV rows after gviz export):
  Row 0       : merged header (Facturación + column headers)
  Rows  1-18  : Facturación
  Rows 19-33  : Clientes Activos
  Rows 34-48  : Gasto Medio por Socio
  Rows 49-63  : Altas
  Rows 64-78  : Bajas  (alternating count/% per month, cols 2-25)
  Rows 79-93  : Ocupación Clases
  Rows 94-99  : Lifetime Value
  Rows 100-105: Permanencia Media

DETALLE FACTURACIÓN sheets: groups of year-rows per service, delimited
by the year repeating (signals new service) or a sub-header "Enero…" row.
"""

import csv
import io
import time
from urllib.parse import quote_plus

import requests

import config

MONTHS = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN",
          "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"]

_cache: dict = {}
_cache_ts: dict = {}


# ── helpers ──────────────────────────────────────────────────────────────────

def _to_float(v) -> float | None:
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "#DIV/0!", "??", "#N/A", "#VALUE!", "#REF!"):
        return None
    # strip symbols
    s = s.replace("€", "").replace("%", "").replace("\xa0", "").replace(" ", "")
    if not s:
        return None
    # European number formats
    if "," in s and "." in s:
        # 1.234,56  → thousands dot, decimal comma
        s = s.replace(".", "").replace(",", ".")
    elif "," in s:
        # 1234,56   → decimal comma only
        s = s.replace(",", ".")
    elif "." in s:
        parts = s.split(".")
        # 1.030  → thousands dot (3 digits after dot, integer-looking left)
        if len(parts) == 2 and len(parts[1]) == 3 and parts[0].lstrip("-").isdigit():
            s = s.replace(".", "")
        # else leave as decimal: 1.5, 12.95, etc.
    try:
        return float(s)
    except ValueError:
        return None


def _try_year(s: str) -> int | None:
    try:
        y = int(float(s.strip()))
        return y if 2000 <= y <= 2035 else None
    except (ValueError, AttributeError):
        return None


def _fetch_csv(sheet_name: str) -> list[list[str]]:
    now = time.time()
    if sheet_name in _cache and now - _cache_ts.get(sheet_name, 0) < config.CACHE_TTL:
        return _cache[sheet_name]
    url = (
        f"https://docs.google.com/spreadsheets/d/{config.SHEET_ID}"
        f"/gviz/tq?tqx=out:csv&sheet={quote_plus(sheet_name)}"
    )
    r = requests.get(url, timeout=15)
    r.raise_for_status()
    rows = list(csv.reader(io.StringIO(r.text)))
    _cache[sheet_name] = rows
    _cache_ts[sheet_name] = now
    return rows


def invalidate_cache():
    _cache.clear()
    _cache_ts.clear()


# ── CUADRO MANDOS parsing ────────────────────────────────────────────────────

# Fixed row slices (verified against live CSV export, 106 rows total)
_SECTIONS = {
    "facturacion":     (1, 19),
    "clientes":        (19, 34),
    "gasto_medio":     (34, 49),
    "altas":           (49, 64),
    "bajas":           (64, 79),
    "ocupacion":       (79, 94),
    "ltv":             (94, 100),
    "permanencia":     (100, 106),
}


def _parse_standard_block(rows: list) -> dict:
    """
    Parse a block where monthly data is in cols 2-13, total in col 14.
    Returns {center: {year: {month: value, 'total': value, 'media': value}}}
    """
    result: dict = {}
    current_year = None

    for row in rows:
        if len(row) < 3:
            continue
        year = _try_year(row[0])
        center = row[1].strip().upper() if len(row) > 1 else ""

        if year:
            current_year = year
        if not current_year or center in ("", "TOTAL"):
            continue
        if center not in ("PARLA", "LAS ROSAS", "GETAFE"):
            continue

        monthly = {}
        for j, m in enumerate(MONTHS):
            col = j + 2
            monthly[m] = _to_float(row[col]) if col < len(row) else None

        total = _to_float(row[14]) if len(row) > 14 else None
        media = _to_float(row[15]) if len(row) > 15 else None

        result.setdefault(center, {})[current_year] = {
            **monthly, "TOTAL": total, "MEDIA": media
        }
    return result


def _parse_bajas_block(rows: list) -> dict:
    """
    Bajas: alternating (count, pct%) per month starting at col 2.
    Col layout: [year, center, ENE_n, ENE_%, FEB_n, FEB_%, ..., DIC_n, DIC_%, total, media_n, media_%]
    """
    result: dict = {}
    current_year = None

    for row in rows:
        if len(row) < 3:
            continue
        year = _try_year(row[0])
        center = row[1].strip().upper() if len(row) > 1 else ""

        if year:
            current_year = year
        if not current_year or center in ("", "TOTAL"):
            continue
        if center not in ("PARLA", "LAS ROSAS", "GETAFE"):
            continue

        monthly = {}
        for j, m in enumerate(MONTHS):
            ci = j * 2 + 2
            pi = j * 2 + 3
            count = _to_float(row[ci]) if ci < len(row) else None
            pct_raw = row[pi].strip() if pi < len(row) else ""
            pct = _to_float(pct_raw)
            # percentages stored as "7,55%" → float 7.55 already via _to_float
            # but some are stored as decimals 0.0755 → convert
            if pct is not None and pct < 1:
                pct = round(pct * 100, 2)
            monthly[m] = {"n": count, "pct": pct}

        total = _to_float(row[26]) if len(row) > 26 else None
        result.setdefault(center, {})[current_year] = {
            "monthly": monthly, "TOTAL": total
        }
    return result


def _parse_cuadro_mandos() -> dict:
    rows = _fetch_csv("CUADRO MANDOS")
    out = {}
    for key, (start, end) in _SECTIONS.items():
        block = rows[start:end]
        if key == "bajas":
            out[key] = _parse_bajas_block(block)
        else:
            out[key] = _parse_standard_block(block)
    return out


# ── DETALLE FACTURACIÓN parsing ──────────────────────────────────────────────

_DETALLE_SERVICES = {
    "DETALLE FACTURACIÓN PARLA": [
        "Nutrición", "Alimentación", "Equipamiento", "Entreno Personal", "Eventos"
    ],
    "DETALLE FACTURACIÓN LAS ROSAS": [
        "Osteopatía", "Nutrición", "Alimentación", "Equipamiento", "Entreno Personal", "Eventos"
    ],
    "DETALLE FACTURACIÓN GETAFE": [
        "Nutrición", "Alimentación", "Equipamiento", "Entreno Personal", "Eventos"
    ],
}

_MONTH_HEADERS = {
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
    "enero ", "febrero ", "marzo ", "abril ", "mayo ", "junio ",
    "julio ", "agosto ", "septiembre ", "octubre ", "noviembre ", "diciembre ",
}


def _is_service_name(s: str) -> bool:
    s = s.strip()
    if not s:
        return False
    if _try_year(s) is not None:
        return False
    if s.lower().strip() in _MONTH_HEADERS:
        return False
    return True


def _parse_detalle(sheet_name: str, service_order: list) -> dict:
    rows = _fetch_csv(sheet_name)
    result: dict = {}
    service_idx = 0
    current_service = service_order[0] if service_order else None
    seen_years: set = set()

    for row in rows:
        if not row or len(row) < 2:
            continue
        col0 = row[0].strip()
        col2 = row[2].strip() if len(row) > 2 else ""

        # Sub-header row: empty col0, col2 starts with "Enero" → advance service
        if not col0 and col2.lower().startswith("enero"):
            service_idx += 1
            if service_idx < len(service_order):
                current_service = service_order[service_idx]
                seen_years = set()
            continue

        # Explicit service name in col0
        if _is_service_name(col0):
            for si, svc in enumerate(service_order):
                name_clean = svc.lower().replace("ó", "o").replace("ú", "u").replace("é", "e")
                col0_clean = col0.lower().replace("ó", "o").replace("ú", "u").replace("é", "e")
                if name_clean[:6] in col0_clean or col0_clean[:6] in name_clean:
                    service_idx = si
                    current_service = service_order[service_idx]
                    seen_years = set()
                    break
            continue

        year = _try_year(col0)
        if year is None or not current_service:
            continue

        # Repeated year → new service group
        if year in seen_years:
            service_idx += 1
            if service_idx < len(service_order):
                current_service = service_order[service_idx]
                seen_years = {year}
            else:
                break
        else:
            seen_years.add(year)

        monthly = {}
        for j, m in enumerate(MONTHS):
            col = j + 2
            monthly[m] = _to_float(row[col]) if col < len(row) else None
        total = _to_float(row[14]) if len(row) > 14 else None

        result.setdefault(current_service, {})[year] = {**monthly, "TOTAL": total}

    return result


# ── TARIFAS parsing ──────────────────────────────────────────────────────────

def _parse_tarifas() -> dict:
    """Returns pricing data for both centers."""
    tarifas = {}

    # TARIFAS PARLA (cols: [None, nombre, precio_2025, clases_2025, eur_clase_2025, None, nombre, precio_2026, ...])
    rows_parla = _fetch_csv("TARIFAS PARLA")
    parla = {"2025": {}, "2026": {}}
    for row in rows_parla[3:]:  # skip headers
        if len(row) < 5 or not row[1].strip():
            continue
        nombre = row[1].strip()
        parla["2025"][nombre] = {
            "precio": _to_float(row[2]),
            "clases": _to_float(row[3]),
            "eur_clase": _to_float(row[4]),
        }
        if len(row) > 8 and row[7].strip():
            parla["2026"][row[7].strip()] = {
                "precio": _to_float(row[7]) if False else _to_float(row[7]),
                "clases": _to_float(row[8]) if len(row) > 8 else None,
                "eur_clase": _to_float(row[9]) if len(row) > 9 else None,
            }
            # fix: col7 might be nombre or precio
            nombre26 = row[6].strip() if len(row) > 6 and row[6].strip() else nombre
            parla["2026"][nombre26] = {
                "precio": _to_float(row[7]),
                "clases": _to_float(row[8]) if len(row) > 8 else None,
                "eur_clase": _to_float(row[9]) if len(row) > 9 else None,
            }
    tarifas["PARLA"] = parla

    # TARIFAS LAS ROSAS
    rows_rosas = _fetch_csv("TARIFAS LAS ROSAS")
    rosas = {"2024": {}, "2026": {}}
    for row in rows_rosas[3:]:
        if len(row) < 5 or not row[1].strip():
            continue
        nombre = row[1].strip()
        rosas["2024"][nombre] = {
            "precio": _to_float(row[2]),
            "clases": _to_float(row[3]),
            "eur_clase": _to_float(row[4]),
        }
        if len(row) > 9 and row[6].strip():
            nombre26 = row[6].strip()
            rosas["2026"][nombre26] = {
                "precio": _to_float(row[7]),
                "clases": _to_float(row[8]) if len(row) > 8 else None,
                "eur_clase": _to_float(row[9]) if len(row) > 9 else None,
            }
    tarifas["LAS ROSAS"] = rosas

    return tarifas


# ── public API ────────────────────────────────────────────────────────────────

def get_all_data() -> dict:
    cuadro = _parse_cuadro_mandos()
    detalle = {
        "PARLA": _parse_detalle(
            "DETALLE FACTURACIÓN PARLA",
            _DETALLE_SERVICES["DETALLE FACTURACIÓN PARLA"]
        ),
        "LAS ROSAS": _parse_detalle(
            "DETALLE FACTURACIÓN LAS ROSAS",
            _DETALLE_SERVICES["DETALLE FACTURACIÓN LAS ROSAS"]
        ),
        "GETAFE": _parse_detalle(
            "DETALLE FACTURACIÓN GETAFE",
            _DETALLE_SERVICES["DETALLE FACTURACIÓN GETAFE"]
        ),
    }
    tarifas = _parse_tarifas()
    return {**cuadro, "detalle": detalle, "tarifas": tarifas}
EOF

# ── Templates ────────────────────────────────────────────────────────────────

cat > "${APP_DIR}/templates/base.html" << 'EOF'
<!doctype html>
<html lang="es" data-bs-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}CrossFit MPO — Dashboard{% endblock %}</title>
  <link href="{{ url_for('static', filename='vendor/bootstrap.min.css') }}" rel="stylesheet">
  <link href="{{ url_for('static', filename='vendor/bootstrap-icons.css') }}" rel="stylesheet">
  <link href="{{ url_for('static', filename='css/style.css') }}" rel="stylesheet">
</head>
<body>

{% if session.logged_in %}
<nav class="navbar navbar-expand-lg navbar-dark bg-black border-bottom border-secondary">
  <div class="container-fluid px-4">
    <a class="navbar-brand d-flex align-items-center gap-2" href="{{ url_for('dashboard') }}">
      <span class="brand-icon">⚡</span>
      <span class="fw-bold">CrossFit MPO</span>
      <span class="text-muted small d-none d-sm-inline">Cuadro de Mandos</span>
    </a>

    <div class="d-flex align-items-center gap-3 ms-auto">
      <!-- Vista toggle -->
      <div class="btn-group btn-group-sm" role="group">
        <a href="{{ url_for('dashboard') }}"
           class="btn btn-outline-secondary {% if request.endpoint == 'dashboard' %}active{% endif %}">
          <i class="bi bi-grid-3x3-gap"></i> Resumen
        </a>
        <a href="{{ url_for('detalle') }}"
           class="btn btn-outline-secondary {% if request.endpoint == 'detalle' %}active{% endif %}">
          <i class="bi bi-bar-chart-line"></i> Detalle
        </a>
      </div>

      <button id="btnRefresh" class="btn btn-sm btn-outline-primary" title="Actualizar datos">
        <i class="bi bi-arrow-clockwise"></i>
      </button>

      <span class="text-muted small d-none d-md-inline">
        <i class="bi bi-person-circle"></i> {{ session.username }}
      </span>

      <a href="{{ url_for('logout') }}" class="btn btn-sm btn-outline-danger">
        <i class="bi bi-box-arrow-right"></i>
      </a>
    </div>
  </div>
</nav>
{% endif %}

<main class="{% if session.logged_in %}pt-3{% endif %}">
  {% block content %}{% endblock %}
</main>

<script src="{{ url_for('static', filename='vendor/bootstrap.bundle.min.js') }}"></script>
<script src="{{ url_for('static', filename='vendor/chart.umd.min.js') }}"></script>
<script>
// Refresh button
document.getElementById('btnRefresh')?.addEventListener('click', async function() {
  this.disabled = true;
  this.innerHTML = '<span class="spinner-border spinner-border-sm"></span>';
  try {
    await fetch('/api/refresh', {method:'POST'});
    location.reload();
  } catch(e) {
    location.reload();
  }
});
</script>
{% block scripts %}{% endblock %}
</body>
</html>
EOF

cat > "${APP_DIR}/templates/login.html" << 'EOF'
<!doctype html>
<html lang="es" data-bs-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CrossFit MPO — Acceso</title>
  <link href="{{ url_for('static', filename='vendor/bootstrap.min.css') }}" rel="stylesheet">
  <link href="{{ url_for('static', filename='css/style.css') }}" rel="stylesheet">
</head>
<body class="login-body d-flex align-items-center justify-content-center min-vh-100">

<div class="login-card p-4 p-md-5 rounded-4 shadow-lg" style="width:100%;max-width:400px">
  <div class="text-center mb-4">
    <div class="brand-icon-lg mb-3">⚡</div>
    <h1 class="h3 fw-bold mb-1">CrossFit MPO</h1>
    <p class="text-muted mb-0">Cuadro de Mandos Integral</p>
  </div>

  {% if error %}
  <div class="alert alert-danger py-2 small">
    <i class="bi bi-exclamation-triangle-fill me-1"></i>{{ error }}
  </div>
  {% endif %}

  <form method="post" action="{{ url_for('login') }}">
    <div class="mb-3">
      <label class="form-label small text-muted">Usuario</label>
      <input type="text" name="username" class="form-control form-control-lg bg-dark border-secondary"
             autocomplete="username" required autofocus>
    </div>
    <div class="mb-4">
      <label class="form-label small text-muted">Contraseña</label>
      <input type="password" name="password" class="form-control form-control-lg bg-dark border-secondary"
             autocomplete="current-password" required>
    </div>
    <button type="submit" class="btn btn-primary btn-lg w-100 fw-semibold">
      Entrar
    </button>
  </form>
</div>

<link href="{{ url_for('static', filename='vendor/bootstrap-icons.css') }}" rel="stylesheet">
<script src="{{ url_for('static', filename='vendor/bootstrap.bundle.min.js') }}"></script>
</body>
</html>
EOF

cat > "${APP_DIR}/templates/simple.html" << 'EOF'
{% extends "base.html" %}
{% block title %}Resumen — CrossFit MPO{% endblock %}

{% block content %}
<div class="container-fluid px-4 pb-5">

  <!-- Loading spinner -->
  <div id="loadingState" class="text-center py-5">
    <div class="spinner-border text-primary" role="status"></div>
    <p class="mt-3 text-muted">Cargando datos…</p>
  </div>

  <!-- Dashboard content -->
  <div id="dashContent" style="display:none">

    <!-- Header -->
    <div class="d-flex align-items-center justify-content-between mb-4 flex-wrap gap-2">
      <div>
        <h2 class="fw-bold mb-0">Vista Resumen</h2>
        <small class="text-muted" id="lastUpdated"></small>
      </div>
      <div class="d-flex gap-2 align-items-center">
        <span class="badge bg-secondary" id="currentYearBadge"></span>
        <a href="{{ url_for('detalle') }}" class="btn btn-sm btn-outline-primary">
          Ver detalle completo <i class="bi bi-arrow-right"></i>
        </a>
      </div>
    </div>

    <!-- KPI Cards -->
    <div class="row g-3 mb-4" id="kpiCards">
      <div class="col-6 col-md-3">
        <div class="kpi-card card h-100 p-3">
          <div class="kpi-icon text-primary"><i class="bi bi-currency-euro"></i></div>
          <div class="kpi-label">Facturación acumulada</div>
          <div class="kpi-value" id="kpiFact">—</div>
          <div class="kpi-sub" id="kpiFactSub"></div>
        </div>
      </div>
      <div class="col-6 col-md-3">
        <div class="kpi-card card h-100 p-3">
          <div class="kpi-icon text-success"><i class="bi bi-people-fill"></i></div>
          <div class="kpi-label">Socios activos</div>
          <div class="kpi-value" id="kpiClientes">—</div>
          <div class="kpi-sub" id="kpiClientesSub"></div>
        </div>
      </div>
      <div class="col-6 col-md-3">
        <div class="kpi-card card h-100 p-3">
          <div class="kpi-icon text-warning"><i class="bi bi-person-lines-fill"></i></div>
          <div class="kpi-label">Altas vs Bajas</div>
          <div class="kpi-value" id="kpiAltasBajas">—</div>
          <div class="kpi-sub" id="kpiAltasBajasSub"></div>
        </div>
      </div>
      <div class="col-6 col-md-3">
        <div class="kpi-card card h-100 p-3">
          <div class="kpi-icon text-info"><i class="bi bi-activity"></i></div>
          <div class="kpi-label">Ocupación clases</div>
          <div class="kpi-value" id="kpiOcupacion">—</div>
          <div class="kpi-sub" id="kpiOcupacionSub"></div>
        </div>
      </div>
    </div>

    <!-- Charts row -->
    <div class="row g-3 mb-4">
      <div class="col-12 col-lg-8">
        <div class="card p-3 h-100">
          <div class="d-flex justify-content-between align-items-center mb-3">
            <h6 class="fw-semibold mb-0">Facturación mensual por centro</h6>
            <select id="yearSelectFact" class="form-select form-select-sm w-auto bg-dark border-secondary text-white"></select>
          </div>
          <div style="position:relative;height:280px">
            <canvas id="chartFact"></canvas>
          </div>
        </div>
      </div>
      <div class="col-12 col-lg-4">
        <div class="card p-3 h-100">
          <h6 class="fw-semibold mb-3">Clientes activos (último mes disponible)</h6>
          <div style="position:relative;height:280px">
            <canvas id="chartClientes"></canvas>
          </div>
        </div>
      </div>
    </div>

    <!-- Second charts row -->
    <div class="row g-3 mb-4">
      <div class="col-12 col-md-6">
        <div class="card p-3 h-100">
          <h6 class="fw-semibold mb-3">Evolución anual facturación (€)</h6>
          <div style="position:relative;height:220px">
            <canvas id="chartFactAnual"></canvas>
          </div>
        </div>
      </div>
      <div class="col-12 col-md-6">
        <div class="card p-3 h-100">
          <h6 class="fw-semibold mb-3">Altas vs Bajas mensuales</h6>
          <div style="position:relative;height:220px">
            <canvas id="chartAltasBajas"></canvas>
          </div>
        </div>
      </div>
    </div>

    <!-- Resumen tabla por centro -->
    <div class="card p-3">
      <h6 class="fw-semibold mb-3">Comparativa centros — año en curso</h6>
      <div class="table-responsive">
        <table class="table table-dark table-hover table-sm align-middle mb-0">
          <thead class="table-secondary">
            <tr>
              <th>Centro</th>
              <th class="text-end">Facturación acum.</th>
              <th class="text-end">Socios activos</th>
              <th class="text-end">Media altas/mes</th>
              <th class="text-end">Media bajas/mes</th>
              <th class="text-end">Ocupación media</th>
              <th class="text-end">LTV medio</th>
            </tr>
          </thead>
          <tbody id="resumenTabla"></tbody>
        </table>
      </div>
    </div>

  </div><!-- /dashContent -->
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', filename='js/utils.js') }}"></script>
<script src="{{ url_for('static', filename='js/simple.js') }}"></script>
{% endblock %}
EOF

cat > "${APP_DIR}/templates/full.html" << 'EOF'
{% extends "base.html" %}
{% block title %}Detalle — CrossFit MPO{% endblock %}

{% block content %}
<div class="container-fluid px-4 pb-5">

  <div id="loadingState" class="text-center py-5">
    <div class="spinner-border text-primary" role="status"></div>
    <p class="mt-3 text-muted">Cargando datos…</p>
  </div>

  <div id="dashContent" style="display:none">

    <!-- Header + filtros -->
    <div class="d-flex align-items-center justify-content-between mb-3 flex-wrap gap-3">
      <h2 class="fw-bold mb-0">Vista Detalle</h2>
      <div class="d-flex gap-2 flex-wrap align-items-center">
        <!-- Centro selector -->
        <div class="btn-group btn-group-sm" role="group" id="centerFilter">
          <button class="btn btn-primary center-btn" data-center="ALL">Todos</button>
          <button class="btn btn-outline-secondary center-btn" data-center="PARLA">Parla</button>
          <button class="btn btn-outline-secondary center-btn" data-center="LAS ROSAS">Las Rosas</button>
          <button class="btn btn-outline-secondary center-btn" data-center="GETAFE">Getafe</button>
        </div>
        <!-- Año selector -->
        <select id="yearSelect" class="form-select form-select-sm w-auto bg-dark border-secondary text-white"></select>
      </div>
    </div>

    <!-- Sección: Financiero -->
    <h5 class="section-title mt-4 mb-3"><i class="bi bi-currency-euro"></i> Financiero</h5>
    <div class="row g-3 mb-4">
      <div class="col-12 col-xl-8">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Facturación mensual (€)</h6>
          <div style="height:260px"><canvas id="chartFactMensual"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-xl-4">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Gasto medio por socio (€/mes)</h6>
          <div style="height:260px"><canvas id="chartGasto"></canvas></div>
        </div>
      </div>
    </div>
    <div class="row g-3 mb-4">
      <div class="col-12 col-md-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Facturación anual total</h6>
          <div style="height:220px"><canvas id="chartFactAnual"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-md-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Lifetime Value (€)</h6>
          <div style="height:220px"><canvas id="chartLTV"></canvas></div>
        </div>
      </div>
    </div>

    <!-- Sección: Socios -->
    <h5 class="section-title mt-4 mb-3"><i class="bi bi-people"></i> Socios</h5>
    <div class="row g-3 mb-4">
      <div class="col-12 col-xl-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Usuarios totales mes a mes por centro</h6>
          <div style="height:300px"><canvas id="chartClientesMes"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-xl-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Altas mensuales</h6>
          <div style="height:240px"><canvas id="chartAltas"></canvas></div>
        </div>
      </div>
    </div>
    <div class="row g-3 mb-4">
      <div class="col-12 col-md-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Bajas mensuales (nº)</h6>
          <div style="height:220px"><canvas id="chartBajas"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-md-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Tasa de baja mensual (%)</h6>
          <div style="height:220px"><canvas id="chartBajasPct"></canvas></div>
        </div>
      </div>
    </div>
    <div class="row g-3 mb-4">
      <div class="col-12 col-md-6">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Permanencia media (meses)</h6>
          <div style="height:200px"><canvas id="chartPermanencia"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-md-6">
        <div class="card p-3 h-100">
          <h6 class="fw-semibold mb-3">KPIs socios — resumen anual</h6>
          <div class="table-responsive">
            <table class="table table-dark table-sm mb-0 align-middle" id="tablaSocios">
              <thead class="table-secondary">
                <tr>
                  <th>Centro</th><th class="text-end">Clientes</th>
                  <th class="text-end">Altas/mes</th><th class="text-end">Bajas/mes</th>
                  <th class="text-end">Baja %</th><th class="text-end">Perm.</th>
                </tr>
              </thead>
              <tbody id="tablaSociosBody"></tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    <!-- Sección: Clases -->
    <h5 class="section-title mt-4 mb-3"><i class="bi bi-activity"></i> Ocupación de Clases</h5>
    <div class="row g-3 mb-4">
      <div class="col-12 col-xl-8">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Ocupación mensual (%)</h6>
          <div style="height:260px"><canvas id="chartOcupacion"></canvas></div>
        </div>
      </div>
      <div class="col-12 col-xl-4">
        <div class="card p-3">
          <h6 class="fw-semibold mb-3">Evolución media anual (%)</h6>
          <div style="height:260px"><canvas id="chartOcupacionAnual"></canvas></div>
        </div>
      </div>
    </div>

    <!-- Sección: Servicios adicionales -->
    <h5 class="section-title mt-4 mb-3"><i class="bi bi-grid-fill"></i> Servicios Adicionales</h5>
    <div class="row g-3 mb-4" id="serviciosCards"></div>

    <!-- Sección: Tarifas -->
    <h5 class="section-title mt-4 mb-3"><i class="bi bi-tags-fill"></i> Tarifas</h5>
    <div class="row g-3 mb-4" id="tarifasContainer"></div>

  </div><!-- /dashContent -->
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', filename='js/utils.js') }}"></script>
<script src="{{ url_for('static', filename='js/full.js') }}"></script>
{% endblock %}
EOF

# ── Static assets ────────────────────────────────────────────────────────────

cat > "${APP_DIR}/static/css/style.css" << 'EOF'
/* ── Variables ──────────────────────────────────────────────── */
:root {
  --accent:    #E8650A;
  --accent-lt: rgba(232, 101, 10, 0.15);
  --card-bg:   #1a1a1a;
  --card-border: rgba(255,255,255,0.08);
}

/* ── Base ───────────────────────────────────────────────────── */
body {
  background: #111;
  color: #e0e0e0;
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
}

/* ── Login ──────────────────────────────────────────────────── */
.login-body { background: radial-gradient(ellipse at 50% 0%, #1a1a2e 0%, #111 70%); }
.login-card  { background: #1a1a1a; border: 1px solid var(--card-border); }
.brand-icon-lg { font-size: 3rem; filter: drop-shadow(0 0 12px var(--accent)); }

/* ── Navbar ─────────────────────────────────────────────────── */
.navbar { border-color: var(--card-border) !important; }
.brand-icon { font-size: 1.4rem; filter: drop-shadow(0 0 6px var(--accent)); }

/* ── Cards ──────────────────────────────────────────────────── */
.card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
}

/* ── KPI Cards ──────────────────────────────────────────────── */
.kpi-card {
  position: relative;
  overflow: hidden;
  transition: border-color .2s, transform .2s;
}
.kpi-card:hover { border-color: var(--accent); transform: translateY(-2px); }
.kpi-icon  { font-size: 1.5rem; margin-bottom: .25rem; }
.kpi-label { font-size: .7rem; text-transform: uppercase; letter-spacing: .08em; color: #888; margin-bottom: .15rem; }
.kpi-value { font-size: 1.7rem; font-weight: 700; line-height: 1; }
.kpi-sub   { font-size: .72rem; color: #999; margin-top: .25rem; }

/* ── Section titles ─────────────────────────────────────────── */
.section-title {
  font-size: 1rem;
  font-weight: 600;
  color: var(--accent);
  text-transform: uppercase;
  letter-spacing: .06em;
  border-bottom: 1px solid var(--accent-lt);
  padding-bottom: .5rem;
}

/* ── Tables ─────────────────────────────────────────────────── */
.table-dark { --bs-table-bg: transparent; }
.table > :not(caption) > * > * { padding: .45rem .75rem; }

/* ── Center badge colors ────────────────────────────────────── */
.badge-parla    { background: #3b82f6; }
.badge-lasrosas { background: #10b981; }
.badge-getafe   { background: #f59e0b; }

.dot-parla    { display:inline-block;width:10px;height:10px;border-radius:50%;background:#3b82f6;margin-right:5px; }
.dot-lasrosas { display:inline-block;width:10px;height:10px;border-radius:50%;background:#10b981;margin-right:5px; }
.dot-getafe   { display:inline-block;width:10px;height:10px;border-radius:50%;background:#f59e0b;margin-right:5px; }

/* ── Tarifa table ───────────────────────────────────────────── */
.tarifa-card .table th { white-space: nowrap; }
.tarifa-badge { font-size: .65rem; vertical-align: middle; }

/* ── Servicio mini-card ─────────────────────────────────────── */
.servicio-bar { height: 6px; border-radius: 3px; background: var(--accent); }

/* ── Chart.js global defaults ───────────────────────────────── */
canvas { display: block; }

/* ── Scrollbar ──────────────────────────────────────────────── */
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: #111; }
::-webkit-scrollbar-thumb { background: #333; border-radius: 3px; }

/* ── Responsive ─────────────────────────────────────────────── */
@media (max-width: 576px) {
  .kpi-value { font-size: 1.3rem; }
  h2 { font-size: 1.3rem; }
}
EOF

cat > "${APP_DIR}/static/js/utils.js" << 'EOF'
/* ── Shared utilities ─────────────────────────────────────── */

const MONTHS     = ["ENE","FEB","MAR","ABR","MAY","JUN","JUL","AGO","SEP","OCT","NOV","DIC"];
const MONTHS_ES  = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"];
const CENTERS    = ["PARLA", "LAS ROSAS", "GETAFE"];

const C_COLORS = {
  "PARLA":     "#3b82f6",
  "LAS ROSAS": "#10b981",
  "GETAFE":    "#f59e0b",
};
const C_COLORS_BG = {
  "PARLA":     "rgba(59,130,246,0.15)",
  "LAS ROSAS": "rgba(16,185,129,0.15)",
  "GETAFE":    "rgba(245,158,11,0.15)",
};
const DOT_CLASS = {
  "PARLA":     "dot-parla",
  "LAS ROSAS": "dot-lasrosas",
  "GETAFE":    "dot-getafe",
};

function fmt(v, decimals=0, suffix='') {
  if (v == null) return '—';
  return v.toLocaleString('es-ES', {minimumFractionDigits:decimals,maximumFractionDigits:decimals}) + suffix;
}
function fmtEur(v)  { return v == null ? '—' : fmt(v) + ' €'; }
function fmtPct(v)  { return v == null ? '—' : fmt(v,1) + '%'; }

/* Latest non-null value in a month series for a given center/year */
function latestVal(section, center, year) {
  const y = section?.[center]?.[year];
  if (!y) return null;
  for (let i = MONTHS.length - 1; i >= 0; i--) {
    if (y[MONTHS[i]] != null) return y[MONTHS[i]];
  }
  return y.TOTAL ?? null;
}

/* Sum all non-null months */
function sumMonths(yearObj) {
  if (!yearObj) return null;
  let s = 0, cnt = 0;
  for (const m of MONTHS) { if (yearObj[m] != null) { s += yearObj[m]; cnt++; } }
  return cnt ? s : null;
}

/* Average of all non-null months */
function avgMonths(yearObj) {
  if (!yearObj) return null;
  let s = 0, cnt = 0;
  for (const m of MONTHS) { if (yearObj[m] != null) { s += yearObj[m]; cnt++; } }
  return cnt ? s / cnt : null;
}

/* Current year (or latest year with data) */
function currentYear(section) {
  const years = new Set();
  for (const center of CENTERS) {
    Object.keys(section?.[center] ?? {}).forEach(y => years.add(+y));
  }
  return Math.max(...years);
}

/* All years present in a section */
function allYears(section) {
  const years = new Set();
  for (const center of CENTERS) {
    Object.keys(section?.[center] ?? {}).forEach(y => years.add(+y));
  }
  return [...years].sort();
}

/* Chart.js defaults */
Chart.defaults.color = '#888';
Chart.defaults.borderColor = 'rgba(255,255,255,0.06)';
Chart.defaults.plugins.legend.labels.boxWidth = 12;
Chart.defaults.plugins.legend.labels.padding  = 16;
Chart.defaults.plugins.tooltip.backgroundColor = '#1a1a1a';
Chart.defaults.plugins.tooltip.borderColor     = 'rgba(255,255,255,0.12)';
Chart.defaults.plugins.tooltip.borderWidth     = 1;
Chart.defaults.plugins.tooltip.padding         = 10;

function makeLineDataset(label, data, center) {
  return {
    label, data,
    borderColor: C_COLORS[center] ?? '#aaa',
    backgroundColor: C_COLORS_BG[center] ?? 'rgba(170,170,170,0.1)',
    borderWidth: 2,
    pointRadius: 3,
    pointHoverRadius: 5,
    tension: 0.3,
    fill: false,
  };
}

function makeBarDataset(label, data, center) {
  return {
    label, data,
    backgroundColor: C_COLORS[center] ?? '#aaa',
    borderRadius: 4,
    borderSkipped: false,
  };
}

function destroyChart(id) {
  const c = Chart.getChart(id);
  if (c) c.destroy();
}

/* Global data holder */
window.DASH = {};

/* Fetch data from API */
async function loadData() {
  const resp = await fetch('/api/data');
  if (!resp.ok) throw new Error('Error al cargar datos');
  const json = await resp.json();
  if (!json.ok) throw new Error(json.error ?? 'Error desconocido');
  return json.data;
}
EOF

cat > "${APP_DIR}/static/js/simple.js" << 'EOF'
/* ── Vista Resumen ────────────────────────────────────────── */

(async function () {
  try {
    const data = await loadData();
    window.DASH = data;
    renderSimple(data);
  } catch (e) {
    document.getElementById('loadingState').innerHTML =
      `<div class="alert alert-danger mx-auto" style="max-width:400px">
         <i class="bi bi-exclamation-triangle"></i> ${e.message}
       </div>`;
  }
})();

function renderSimple(d) {
  const CY = currentYear(d.facturacion);
  document.getElementById('currentYearBadge').textContent = CY;
  document.getElementById('lastUpdated').textContent =
    'Actualizado: ' + new Date().toLocaleString('es-ES');

  // ── KPI cards ────────────────────────────────────────────────
  // Facturación acumulada año actual (suma todos los centros)
  let factTotal = 0, factPrevTotal = 0;
  for (const center of CENTERS) {
    factTotal     += sumMonths(d.facturacion?.[center]?.[CY]) ?? 0;
    factPrevTotal += sumMonths(d.facturacion?.[center]?.[CY-1]) ?? 0;
  }
  document.getElementById('kpiFact').textContent = fmtEur(factTotal);
  const pctFact = factPrevTotal ? ((factTotal - factPrevTotal) / factPrevTotal * 100) : null;
  document.getElementById('kpiFactSub').innerHTML =
    pctFact != null
      ? `<span class="${pctFact>=0?'text-success':'text-danger'}">${pctFact>=0?'▲':'▼'} ${fmt(Math.abs(pctFact),1)}% vs ${CY-1}</span>`
      : `vs año anterior: —`;

  // Socios activos (suma últimos disponibles)
  let sociosTotal = 0, sociosByCentro = {};
  for (const center of CENTERS) {
    const v = latestVal(d.clientes, center, CY);
    if (v != null) { sociosTotal += v; sociosByCentro[center] = v; }
  }
  document.getElementById('kpiClientes').textContent = fmt(sociosTotal);
  document.getElementById('kpiClientesSub').innerHTML =
    CENTERS.filter(c => sociosByCentro[c]).map(c =>
      `<span class="${DOT_CLASS[c]}"></span>${c.replace('LAS ROSAS','L.R.')} ${fmt(sociosByCentro[c])}`
    ).join(' &nbsp;');

  // Altas vs Bajas (promedios mensuales año actual)
  let altasAvg = 0, bajasAvg = 0;
  for (const center of CENTERS) {
    altasAvg += avgMonths(d.altas?.[center]?.[CY]) ?? 0;
    const bajasYC = d.bajas?.[center]?.[CY];
    if (bajasYC?.monthly) {
      const vals = MONTHS.map(m => bajasYC.monthly[m]?.n).filter(v => v != null);
      if (vals.length) bajasAvg += vals.reduce((a,b)=>a+b,0)/vals.length;
    }
  }
  document.getElementById('kpiAltasBajas').innerHTML =
    `<span class="text-success">+${fmt(altasAvg,1)}</span> / <span class="text-danger">-${fmt(bajasAvg,1)}</span>`;
  document.getElementById('kpiAltasBajasSub').textContent = 'altas/bajas por mes (media)';

  // Ocupación
  let ocArr = [];
  for (const center of CENTERS) {
    const avg = avgMonths(d.ocupacion?.[center]?.[CY]);
    if (avg != null) ocArr.push(avg);
  }
  const ocMedia = ocArr.length ? ocArr.reduce((a,b)=>a+b,0)/ocArr.length : null;
  document.getElementById('kpiOcupacion').textContent = fmtPct(ocMedia);
  document.getElementById('kpiOcupacionSub').textContent = 'media todos los centros';

  // ── Facturación mensual por centro ───────────────────────────
  const yearsFact = allYears(d.facturacion);
  const yearSelectFact = document.getElementById('yearSelectFact');
  yearsFact.sort((a,b)=>b-a).forEach(y => {
    const o = document.createElement('option');
    o.value = y; o.textContent = y;
    if (y === CY) o.selected = true;
    yearSelectFact.appendChild(o);
  });

  function drawFactMensual(year) {
    destroyChart('chartFact');
    const datasets = CENTERS
      .filter(c => d.facturacion?.[c]?.[year])
      .map(c => makeBarDataset(c, MONTHS.map(m => d.facturacion[c][year][m] ?? null), c));
    new Chart(document.getElementById('chartFact'), {
      type: 'bar',
      data: { labels: MONTHS_ES, datasets },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { position: 'top' } },
        scales: {
          x: { stacked: false },
          y: { ticks: { callback: v => fmt(v) + '€' } }
        }
      }
    });
  }
  drawFactMensual(CY);
  yearSelectFact.addEventListener('change', () => drawFactMensual(+yearSelectFact.value));

  // ── Clientes activos (último mes, por centro, donut) ─────────
  destroyChart('chartClientes');
  const clientesLabels = CENTERS.filter(c => sociosByCentro[c]);
  new Chart(document.getElementById('chartClientes'), {
    type: 'doughnut',
    data: {
      labels: clientesLabels,
      datasets: [{
        data: clientesLabels.map(c => sociosByCentro[c]),
        backgroundColor: clientesLabels.map(c => C_COLORS[c]),
        borderWidth: 0,
        hoverOffset: 8,
      }]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: {
        legend: { position: 'bottom' },
        tooltip: { callbacks: { label: ctx => ` ${ctx.label}: ${ctx.raw} socios` } }
      },
      cutout: '65%',
    }
  });

  // ── Facturación anual histórica ──────────────────────────────
  destroyChart('chartFactAnual');
  const allYearsSet = new Set();
  for (const c of CENTERS) Object.keys(d.facturacion?.[c] ?? {}).forEach(y => allYearsSet.add(+y));
  const sortedYears = [...allYearsSet].sort();

  new Chart(document.getElementById('chartFactAnual'), {
    type: 'line',
    data: {
      labels: sortedYears,
      datasets: CENTERS
        .filter(c => d.facturacion?.[c])
        .map(c => makeLineDataset(
          c,
          sortedYears.map(y => {
            const yr = d.facturacion[c]?.[y];
            return yr ? (yr.TOTAL ?? sumMonths(yr)) : null;
          }),
          c
        ))
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { position: 'top' } },
      scales: {
        y: { ticks: { callback: v => fmt(v) + '€' } }
      }
    }
  });

  // ── Altas vs Bajas ───────────────────────────────────────────
  destroyChart('chartAltasBajas');
  const altasCY = MONTHS.map(m => {
    let total = 0;
    for (const c of CENTERS) { total += (d.altas?.[c]?.[CY]?.[m] ?? 0); }
    return total || null;
  });
  const bajasCY = MONTHS.map(m => {
    let total = 0;
    for (const c of CENTERS) {
      const v = d.bajas?.[c]?.[CY]?.monthly?.[m]?.n;
      if (v) total += v;
    }
    return total || null;
  });
  new Chart(document.getElementById('chartAltasBajas'), {
    type: 'bar',
    data: {
      labels: MONTHS_ES,
      datasets: [
        { label: 'Altas', data: altasCY, backgroundColor: '#10b981', borderRadius: 4, borderSkipped: false },
        { label: 'Bajas', data: bajasCY.map(v => v ? -v : null), backgroundColor: '#ef4444', borderRadius: 4, borderSkipped: false },
      ]
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      plugins: { legend: { position: 'top' } },
      scales: {
        y: { ticks: { callback: v => Math.abs(v) } }
      }
    }
  });

  // ── Tabla resumen ────────────────────────────────────────────
  const tbody = document.getElementById('resumenTabla');
  tbody.innerHTML = '';
  for (const center of CENTERS) {
    if (!d.facturacion?.[center]) continue;
    const factAcum = sumMonths(d.facturacion[center]?.[CY]);
    const clientes = latestVal(d.clientes, center, CY);
    const altasM   = avgMonths(d.altas?.[center]?.[CY]);
    const bajasYC  = d.bajas?.[center]?.[CY];
    let bajasM = null, bajasPct = null;
    if (bajasYC?.monthly) {
      const ns = MONTHS.map(m=>bajasYC.monthly[m]?.n).filter(v=>v!=null);
      const ps = MONTHS.map(m=>bajasYC.monthly[m]?.pct).filter(v=>v!=null);
      if (ns.length) bajasM = ns.reduce((a,b)=>a+b,0)/ns.length;
      if (ps.length) bajasPct = ps.reduce((a,b)=>a+b,0)/ps.length;
    }
    const ltvVals = MONTHS.map(m => d.ltv?.[center]?.[CY]?.[m]).filter(v=>v!=null);
    const ltvAvg  = ltvVals.length ? ltvVals.reduce((a,b)=>a+b,0)/ltvVals.length : null;
    const dot = `<span class="${DOT_CLASS[center]}"></span>`;
    tbody.insertAdjacentHTML('beforeend',`
      <tr>
        <td>${dot}${center}</td>
        <td class="text-end">${fmtEur(factAcum)}</td>
        <td class="text-end">${fmt(clientes)}</td>
        <td class="text-end text-success">${fmt(altasM,1)}</td>
        <td class="text-end text-danger">${fmt(bajasM,1)}</td>
        <td class="text-end">${fmtPct(bajasPct)}</td>
        <td class="text-end">${fmtEur(ltvAvg)}</td>
      </tr>`);
  }

  // Show content
  document.getElementById('loadingState').style.display = 'none';
  document.getElementById('dashContent').style.display  = '';
}
EOF

cat > "${APP_DIR}/static/js/full.js" << 'EOF'
/* ── Vista Detalle ────────────────────────────────────────── */

let selectedCenter = 'ALL';
let selectedYear   = null;
let globalData     = null;

(async function () {
  try {
    const data = await loadData();
    globalData = data;
    window.DASH = data;
    initFilters(data);
    renderAll();
  } catch (e) {
    document.getElementById('loadingState').innerHTML =
      `<div class="alert alert-danger mx-auto" style="max-width:400px">
         <i class="bi bi-exclamation-triangle"></i> ${e.message}
       </div>`;
  }
})();

function initFilters(d) {
  // Year selector
  const years = allYears(d.facturacion).reverse();
  selectedYear = years[0];
  const sel = document.getElementById('yearSelect');
  years.forEach(y => {
    const o = document.createElement('option');
    o.value = y; o.textContent = y;
    sel.appendChild(o);
  });
  sel.addEventListener('change', () => { selectedYear = +sel.value; renderAll(); });

  // Center filter
  document.querySelectorAll('.center-btn').forEach(btn => {
    btn.addEventListener('click', function() {
      document.querySelectorAll('.center-btn').forEach(b => {
        b.className = 'btn btn-outline-secondary center-btn';
      });
      this.className = 'btn btn-primary center-btn';
      selectedCenter = this.dataset.center;
      renderAll();
    });
  });
}

function activeCenters() {
  return selectedCenter === 'ALL' ? CENTERS : [selectedCenter];
}

function renderAll() {
  const d = globalData;
  if (!d) return;
  drawFactMensual(d);
  drawGasto(d);
  drawFactAnual(d);
  drawLTV(d);
  drawClientesMes(d);
  drawAltas(d);
  drawBajas(d);
  drawBajasPct(d);
  drawPermanencia(d);
  drawTablaSocios(d);
  drawOcupacion(d);
  drawOcupacionAnual(d);
  drawServicios(d);
  drawTarifas(d);
  document.getElementById('loadingState').style.display = 'none';
  document.getElementById('dashContent').style.display  = '';
}

// ── Facturación mensual ──────────────────────────────────────
function drawFactMensual(d) {
  destroyChart('chartFactMensual');
  const centers = activeCenters().filter(c => d.facturacion?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartFactMensual'), {
    type: 'bar',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeBarDataset(c, MONTHS.map(m => d.facturacion[c][selectedYear][m] ?? null), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v)+'€' } } })
  });
}

// ── Gasto medio ─────────────────────────────────────────────
function drawGasto(d) {
  destroyChart('chartGasto');
  const centers = activeCenters().filter(c => d.gasto_medio?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartGasto'), {
    type: 'line',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeLineDataset(c, MONTHS.map(m => d.gasto_medio[c][selectedYear][m] ?? null), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v)+'€' } } })
  });
}

// ── Facturación anual ────────────────────────────────────────
function drawFactAnual(d) {
  destroyChart('chartFactAnual');
  const years = allYears(d.facturacion);
  const centers = activeCenters().filter(c => d.facturacion?.[c]);
  new Chart(document.getElementById('chartFactAnual'), {
    type: 'bar',
    data: {
      labels: years,
      datasets: centers.map(c => makeBarDataset(c,
        years.map(y => { const yr=d.facturacion[c]?.[y]; return yr?(yr.TOTAL??sumMonths(yr)):null; }), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v)+'€' } } })
  });
}

// ── LTV ──────────────────────────────────────────────────────
function drawLTV(d) {
  destroyChart('chartLTV');
  const ltv = d.ltv;
  const years = allYears(ltv);
  const centers = activeCenters().filter(c => ltv?.[c]);
  new Chart(document.getElementById('chartLTV'), {
    type: 'bar',
    data: {
      labels: years,
      datasets: centers.map(c => makeBarDataset(c,
        years.map(y => avgMonths(ltv[c]?.[y])), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v)+'€' } } })
  });
}

// ── Usuarios totales mes a mes por centro ────────────────────
function drawClientesMes(d) {
  destroyChart('chartClientesMes');
  const centers = activeCenters().filter(c => d.clientes?.[c]?.[selectedYear]);
  const canvas = document.getElementById('chartClientesMes');
  const ctx = canvas.getContext('2d');

  function makeGradient(hex) {
    const r = parseInt(hex.slice(1,3),16), g = parseInt(hex.slice(3,5),16), b = parseInt(hex.slice(5,7),16);
    const gr = ctx.createLinearGradient(0, 0, 0, 300);
    gr.addColorStop(0,   `rgba(${r},${g},${b},0.45)`);
    gr.addColorStop(0.6, `rgba(${r},${g},${b},0.12)`);
    gr.addColorStop(1,   `rgba(${r},${g},${b},0.01)`);
    return gr;
  }

  const datasets = centers.map(c => ({
    label: c,
    data: MONTHS.map(m => d.clientes[c][selectedYear][m] ?? null),
    borderColor: C_COLORS[c],
    backgroundColor: makeGradient(C_COLORS[c]),
    borderWidth: 2.5,
    pointRadius: 0,
    pointHoverRadius: 6,
    pointHoverBackgroundColor: C_COLORS[c],
    pointHoverBorderColor: '#fff',
    pointHoverBorderWidth: 2,
    tension: 0.4,
    fill: 'origin',
  }));

  if (centers.length > 1) {
    const totals = MONTHS.map(m => {
      const vals = centers.map(c => d.clientes[c][selectedYear][m]).filter(v => v != null);
      return vals.length ? vals.reduce((a, b) => a + b, 0) : null;
    });
    datasets.push({
      label: 'Total',
      data: totals,
      borderColor: 'rgba(255,255,255,0.55)',
      backgroundColor: 'transparent',
      borderWidth: 2,
      borderDash: [6, 3],
      pointRadius: 0,
      pointHoverRadius: 5,
      tension: 0.4,
      fill: false,
    });
  }

  new Chart(canvas, {
    type: 'line',
    data: { labels: MONTHS_ES, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { position: 'top' },
        tooltip: {
          callbacks: {
            label: ctx => ` ${ctx.dataset.label}: ${fmt(ctx.parsed.y ?? 0)} socios`
          }
        }
      },
      scales: {
        x: {},
        y: {
          beginAtZero: false,
          ticks: { callback: v => fmt(v) }
        }
      }
    }
  });
}

// ── Altas ────────────────────────────────────────────────────
function drawAltas(d) {
  destroyChart('chartAltas');
  const centers = activeCenters().filter(c => d.altas?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartAltas'), {
    type: 'bar',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeBarDataset(c, MONTHS.map(m => d.altas[c][selectedYear][m] ?? null), c))
    },
    options: chartOpts()
  });
}

// ── Bajas (nº) ───────────────────────────────────────────────
function drawBajas(d) {
  destroyChart('chartBajas');
  const centers = activeCenters().filter(c => d.bajas?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartBajas'), {
    type: 'bar',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => ({
        ...makeBarDataset(c, MONTHS.map(m => d.bajas[c][selectedYear].monthly?.[m]?.n ?? null), c),
        backgroundColor: C_COLORS[c].replace(')', ',0.7)').replace('rgb','rgba').replace('#','')
      }))
    },
    options: chartOpts()
  });
}

// ── Bajas (%) ────────────────────────────────────────────────
function drawBajasPct(d) {
  destroyChart('chartBajasPct');
  const centers = activeCenters().filter(c => d.bajas?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartBajasPct'), {
    type: 'line',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeLineDataset(c,
        MONTHS.map(m => d.bajas[c][selectedYear].monthly?.[m]?.pct ?? null), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v,1)+'%' } } })
  });
}

// ── Permanencia ──────────────────────────────────────────────
function drawPermanencia(d) {
  destroyChart('chartPermanencia');
  const years = allYears(d.permanencia);
  const centers = activeCenters().filter(c => d.permanencia?.[c]);
  new Chart(document.getElementById('chartPermanencia'), {
    type: 'bar',
    data: {
      labels: years,
      datasets: centers.map(c => makeBarDataset(c,
        years.map(y => avgMonths(d.permanencia[c]?.[y])), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v,1)+' m' } } })
  });
}

// ── Tabla socios ─────────────────────────────────────────────
function drawTablaSocios(d) {
  const tbody = document.getElementById('tablaSociosBody');
  tbody.innerHTML = '';
  for (const center of activeCenters()) {
    if (!d.clientes?.[center]) continue;
    const clientes = latestVal(d.clientes, center, selectedYear);
    const altasM   = avgMonths(d.altas?.[center]?.[selectedYear]);
    const bajasYC  = d.bajas?.[center]?.[selectedYear];
    let bajasM=null, bajasPct=null;
    if (bajasYC?.monthly) {
      const ns=MONTHS.map(m=>bajasYC.monthly[m]?.n).filter(v=>v!=null);
      const ps=MONTHS.map(m=>bajasYC.monthly[m]?.pct).filter(v=>v!=null);
      if(ns.length) bajasM=ns.reduce((a,b)=>a+b)/ns.length;
      if(ps.length) bajasPct=ps.reduce((a,b)=>a+b)/ps.length;
    }
    const permAvg = avgMonths(d.permanencia?.[center]?.[selectedYear]);
    const dot = `<span class="${DOT_CLASS[center]}"></span>`;
    tbody.insertAdjacentHTML('beforeend', `
      <tr>
        <td>${dot}${center}</td>
        <td class="text-end">${fmt(clientes)}</td>
        <td class="text-end text-success">${fmt(altasM,1)}</td>
        <td class="text-end text-danger">${fmt(bajasM,1)}</td>
        <td class="text-end">${fmtPct(bajasPct)}</td>
        <td class="text-end">${permAvg!=null ? fmt(permAvg,1)+' m' : '—'}</td>
      </tr>`);
  }
}

// ── Ocupación mensual ────────────────────────────────────────
function drawOcupacion(d) {
  destroyChart('chartOcupacion');
  const centers = activeCenters().filter(c => d.ocupacion?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartOcupacion'), {
    type: 'line',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeLineDataset(c,
        MONTHS.map(m => d.ocupacion[c][selectedYear][m] ?? null), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v,0)+'%' }, max: 100 } })
  });
}

// ── Ocupación anual ──────────────────────────────────────────
function drawOcupacionAnual(d) {
  destroyChart('chartOcupacionAnual');
  const years = allYears(d.ocupacion);
  const centers = activeCenters().filter(c => d.ocupacion?.[c]);
  new Chart(document.getElementById('chartOcupacionAnual'), {
    type: 'line',
    data: {
      labels: years,
      datasets: centers.map(c => makeLineDataset(c,
        years.map(y => avgMonths(d.ocupacion[c]?.[y])), c))
    },
    options: chartOpts({ y: { ticks: { callback: v => fmt(v,1)+'%' } } })
  });
}

// ── Servicios adicionales ────────────────────────────────────
function drawServicios(d) {
  const container = document.getElementById('serviciosCards');
  container.innerHTML = '';

  const allServices = new Set();
  for (const center of CENTERS) {
    Object.keys(d.detalle?.[center] ?? {}).forEach(s => allServices.add(s));
  }

  for (const svc of allServices) {
    const col = document.createElement('div');
    col.className = 'col-12 col-md-6 col-xl-4';

    // Build total per center for this service
    const rows = activeCenters().map(c => {
      const svcData = d.detalle?.[c]?.[svc];
      if (!svcData) return null;
      const yrData = svcData[selectedYear];
      const total = yrData ? (yrData.TOTAL ?? sumMonths(yrData)) : null;
      return { center: c, total };
    }).filter(Boolean);

    const maxVal = Math.max(...rows.map(r => r.total ?? 0));

    const rowsHTML = rows.map(r => `
      <div class="d-flex align-items-center gap-2 mb-2">
        <span class="${DOT_CLASS[r.center]}" style="flex-shrink:0"></span>
        <span class="small text-muted" style="min-width:70px">${r.center}</span>
        <div class="flex-grow-1 bg-secondary rounded" style="height:6px">
          <div class="servicio-bar" style="width:${maxVal?Math.round((r.total??0)/maxVal*100):0}%"></div>
        </div>
        <span class="small fw-semibold ms-1">${fmtEur(r.total)}</span>
      </div>`).join('');

    col.innerHTML = `
      <div class="card p-3 h-100">
        <h6 class="fw-semibold mb-3"><i class="bi bi-boxes text-primary me-1"></i>${svc}</h6>
        ${rowsHTML || '<p class="text-muted small">Sin datos</p>'}
      </div>`;
    container.appendChild(col);
  }
}

// ── Tarifas ──────────────────────────────────────────────────
function drawTarifas(d) {
  const container = document.getElementById('tarifasContainer');
  container.innerHTML = '';

  const centersToShow = selectedCenter === 'ALL' ? ['PARLA', 'LAS ROSAS'] : [selectedCenter];

  for (const center of centersToShow) {
    const tarifasByCentro = d.tarifas?.[center];
    if (!tarifasByCentro) continue;

    const years = Object.keys(tarifasByCentro).sort();
    const col = document.createElement('div');
    col.className = 'col-12 col-md-6';

    let tabsHTML = years.map((y,i) =>
      `<li class="nav-item">
        <button class="nav-link ${i===years.length-1?'active':''}" data-bs-toggle="tab"
                data-bs-target="#tar-${center.replace(' ','')}-${y}">${y}</button>
       </li>`).join('');

    let panelsHTML = years.map((y,i) => {
      const tarifas = tarifasByCentro[y] ?? {};
      const rows = Object.entries(tarifas).map(([name, t]) => `
        <tr>
          <td>${name}</td>
          <td class="text-end fw-semibold">${t.precio ? fmt(t.precio)+'€' : '—'}</td>
          <td class="text-end">${t.clases ?? '—'}</td>
          <td class="text-end text-muted">${t.eur_clase ? fmt(t.eur_clase,2)+'€' : '—'}</td>
        </tr>`).join('');
      return `
        <div class="tab-pane fade ${i===years.length-1?'show active':''}" id="tar-${center.replace(' ','')}-${y}">
          <table class="table table-dark table-sm table-hover mb-0">
            <thead class="table-secondary">
              <tr><th>Tarifa</th><th class="text-end">Precio</th><th class="text-end">Clases</th><th class="text-end">€/Clase</th></tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>`;
    }).join('');

    const dot = `<span class="${DOT_CLASS[center]}"></span>`;
    col.innerHTML = `
      <div class="card p-3 tarifa-card">
        <h6 class="fw-semibold mb-3">${dot} ${center}</h6>
        <ul class="nav nav-tabs nav-tabs-sm mb-3">${tabsHTML}</ul>
        <div class="tab-content">${panelsHTML}</div>
      </div>`;
    container.appendChild(col);
  }
}

// ── Chart options helper ─────────────────────────────────────
function chartOpts(extraScales = {}) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { position: 'top' } },
    scales: {
      x: {},
      y: { beginAtZero: true },
      ...extraScales
    }
  };
}
EOF

# ── 4. Download vendor assets from CDN ──────────────────────────────────────
echo "=== Downloading vendor assets ==="

curl -fsSL "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" \
     -o "${APP_DIR}/static/vendor/bootstrap.min.css"

curl -fsSL "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js" \
     -o "${APP_DIR}/static/vendor/bootstrap.bundle.min.js"

curl -fsSL "https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js" \
     -o "${APP_DIR}/static/vendor/chart.umd.min.js"

curl -fsSL "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" \
     -o "${APP_DIR}/static/vendor/bootstrap-icons.css"

curl -fsSL "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/fonts/bootstrap-icons.woff2" \
     -o "${APP_DIR}/static/vendor/fonts/bootstrap-icons.woff2"

# Fix font path in bootstrap-icons.css
sed -i 's|../fonts/|/static/vendor/fonts/|g' "${APP_DIR}/static/vendor/bootstrap-icons.css"

# ── 5. Python venv and requirements ─────────────────────────────────────────
echo "=== Setting up Python virtual environment ==="
python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --upgrade pip --quiet
"${APP_DIR}/venv/bin/pip" install -r "${APP_DIR}/requirements.txt" --quiet

# ── 6. Set permissions ───────────────────────────────────────────────────────
echo "=== Setting permissions ==="
chown -R www-data:www-data "${APP_DIR}"
chown -R www-data:www-data "${LOG_DIR}"

# ── 7. Systemd service ───────────────────────────────────────────────────────
echo "=== Installing systemd service ==="
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=CrossFit MPO Dashboard (Gunicorn)
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=${APP_DIR}
Environment="SECRET_KEY=${SECRET_KEY}"
ExecStart=${APP_DIR}/venv/bin/gunicorn \
    --workers 2 \
    --bind 127.0.0.1:5050 \
    --timeout 60 \
    --access-logfile ${LOG_DIR}/access.log \
    --error-logfile  ${LOG_DIR}/error.log \
    wsgi:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

# ── 8. Nginx configuration ───────────────────────────────────────────────────
echo "=== Configuring nginx ==="

cat > "/etc/nginx/sites-available/${SERVICE_NAME}" << 'EOF'
server {
    listen 80;
    server_name dashboard.crossfitmpo.com;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    gzip on;
    gzip_types text/plain text/css application/javascript application/json;

    location /static/ {
        alias /opt/crossfitmpo-dashboard/static/;
        expires 7d;
        add_header Cache-Control "public";
    }

    location / {
        proxy_pass         http://127.0.0.1:5050;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30;
        proxy_buffering    off;
    }

    access_log /var/log/nginx/crossfitmpo-dashboard-access.log;
    error_log  /var/log/nginx/crossfitmpo-dashboard-error.log;
}
EOF

# Enable site, remove default, test and reload
ln -sf "/etc/nginx/sites-available/${SERVICE_NAME}" "/etc/nginx/sites-enabled/${SERVICE_NAME}"
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

# ── 9. SSL with certbot ──────────────────────────────────────────────────────
echo "=== Requesting SSL certificate ==="
certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m admin@crossfitmpo.com \
  || echo "⚠️  SSL: ejecuta manualmente: certbot --nginx -d ${DOMAIN}"

# ── Done ─────────────────────────────────────────────────────────────────────
echo "=== Installation complete ==="
systemctl status "${SERVICE_NAME}" --no-pager -l
