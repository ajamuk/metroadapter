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

// ── Clientes activos mensual ─────────────────────────────────
function drawClientesMes(d) {
  destroyChart('chartClientesMes');
  const centers = activeCenters().filter(c => d.clientes?.[c]?.[selectedYear]);
  new Chart(document.getElementById('chartClientesMes'), {
    type: 'line',
    data: {
      labels: MONTHS_ES,
      datasets: centers.map(c => makeLineDataset(c, MONTHS.map(m => d.clientes[c][selectedYear][m] ?? null), c))
    },
    options: chartOpts()
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
