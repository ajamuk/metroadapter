import OutputSection from './OutputSection'

export default function OutputPanel({ center, state }) {
  const { status, data, rawError } = state

  return (
    <div
      className="flex-1 flex flex-col h-full overflow-hidden"
      style={{ backgroundColor: '#0c0c0c' }}
    >
      {status === 'idle' && (
        <div className="flex-1 flex flex-col items-center justify-center gap-4" style={{ color: '#333' }}>
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#333" strokeWidth="1.5">
            <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
          </svg>
          <p style={{ fontFamily: 'JetBrains Mono', fontSize: '13px', color: '#444', textAlign: 'center' }}>
            Pega un WOD y pulsa Adaptar
          </p>
        </div>
      )}

      {status === 'loading' && (
        <div className="flex-1 flex flex-col items-center justify-center gap-4">
          <div
            style={{
              width: '32px',
              height: '32px',
              border: '2px solid #2c2c2c',
              borderTop: '2px solid #f59e0b',
              borderRadius: '50%',
              animation: 'spin 0.8s linear infinite',
            }}
          />
          <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
          <p style={{ fontFamily: 'JetBrains Mono', fontSize: '12px', color: '#555' }}>
            Adaptando para {center?.name ?? '—'}…
          </p>
        </div>
      )}

      {status === 'error' && (
        <div className="flex-1 overflow-y-auto p-4">
          <div
            className="p-4"
            style={{
              backgroundColor: 'rgba(239,68,68,0.08)',
              border: '1px solid rgba(239,68,68,0.3)',
              borderRadius: '4px',
            }}
          >
            <p
              className="text-xs mb-2"
              style={{ fontFamily: 'JetBrains Mono', color: '#f87171', fontWeight: 700 }}
            >
              ERROR DE RESPUESTA
            </p>
            <pre
              className="text-xs whitespace-pre-wrap break-words"
              style={{ fontFamily: 'JetBrains Mono', color: '#f87171' }}
            >
              {rawError}
            </pre>
          </div>
        </div>
      )}

      {status === 'done' && data && (
        <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-3">
          <OutputSection
            title="Entrenamiento adaptado"
            tag={center?.name?.toUpperCase() ?? 'CENTRO'}
            content={data.workout_adaptado}
            mono
            defaultOpen
          />
          <OutputSection
            title="Briefing — Pasos del coach"
            tag="BRIEFING"
            content={data.pasos_briefing}
            mono={false}
            defaultOpen
          />
          <OutputSection
            title="Resound Plan — Parte 1"
            tag="RESOUND"
            content={data.resound_plan_parte1}
            mono={false}
            defaultOpen
          />
          <OutputSection
            title="Resound Plan — Parte 2"
            tag="RESOUND"
            content={data.resound_plan_parte2}
            mono={false}
            defaultOpen={false}
          />
        </div>
      )}
    </div>
  )
}
