import { useState, useEffect } from 'react'

function buildText(data, centerName) {
  return [
    `━━━ ${centerName?.toUpperCase() ?? 'CENTRO'} — ENTRENAMIENTO ADAPTADO ━━━\n${data.workout_adaptado}`,
    `━━━ BRIEFING — PASOS DEL COACH ━━━\n${data.pasos_briefing}`,
    `━━━ RESOUND PLAN — PARTE 1 ━━━\n${data.resound_plan_parte1}`,
    `━━━ RESOUND PLAN — PARTE 2 ━━━\n${data.resound_plan_parte2}`,
  ].join('\n\n')
}

export default function OutputPanel({ center, state }) {
  const { status, data, rawError } = state
  const [text, setText] = useState('')
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (status === 'done' && data) {
      setText(buildText(data, center?.name))
    }
  }, [status, data, center?.name])

  function handleCopy() {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <div
      className="flex-1 flex flex-col h-full overflow-hidden"
      style={{ backgroundColor: '#0c0c0c' }}
    >
      {status === 'idle' && (
        <div className="flex-1 flex flex-col items-center justify-center gap-4">
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
            <p className="text-xs mb-2" style={{ fontFamily: 'JetBrains Mono', color: '#f87171', fontWeight: 700 }}>
              ERROR DE RESPUESTA
            </p>
            <pre className="text-xs whitespace-pre-wrap break-words" style={{ fontFamily: 'JetBrains Mono', color: '#f87171' }}>
              {rawError}
            </pre>
          </div>
        </div>
      )}

      {status === 'done' && data && (
        <div className="flex-1 flex flex-col min-h-0 p-4 gap-2">
          <div className="flex items-center justify-between flex-shrink-0">
            <span
              className="text-xs uppercase tracking-widest"
              style={{ fontFamily: 'JetBrains Mono', color: '#555', fontWeight: 700 }}
            >
              Resultado — editable
            </span>
            <button
              onClick={handleCopy}
              className="text-xs px-3 py-1.5 transition-colors"
              style={{
                fontFamily: 'DM Sans',
                backgroundColor: copied ? 'rgba(34,197,94,0.1)' : 'transparent',
                border: `1px solid ${copied ? '#22c55e' : '#2c2c2c'}`,
                borderRadius: '4px',
                color: copied ? '#22c55e' : '#888',
                cursor: 'pointer',
              }}
            >
              {copied ? '✓ Copiado' : 'Copiar todo'}
            </button>
          </div>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            className="flex-1 w-full text-sm leading-relaxed"
            style={{
              fontFamily: 'JetBrains Mono',
              fontSize: '12px',
              backgroundColor: '#141414',
              border: '1px solid #2c2c2c',
              borderRadius: '4px',
              color: '#d4d4d4',
              padding: '16px',
              resize: 'none',
              outline: 'none',
            }}
          />
        </div>
      )}
    </div>
  )
}
