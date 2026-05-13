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
