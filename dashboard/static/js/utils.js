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
