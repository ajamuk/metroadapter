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
