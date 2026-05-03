import { useState, useEffect } from 'react'

export default function MemoryModal({ center, onSave, onClose }) {
  const [text, setText] = useState(center.memory || '')

  useEffect(() => {
    setText(center.memory || '')
  }, [center.id])

  function handleSave() {
    onSave(center.id, text)
    onClose()
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ backgroundColor: 'rgba(0,0,0,0.85)' }}
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        className="w-full max-w-2xl mx-4 flex flex-col"
        style={{
          backgroundColor: '#1c1c1c',
          border: '1px solid #2c2c2c',
          borderRadius: '4px',
        }}
      >
        <div
          className="flex items-center justify-between px-6 py-4"
          style={{ borderBottom: '1px solid #2c2c2c' }}
        >
          <div>
            <p
              className="text-xs uppercase tracking-widest mb-1"
              style={{ color: '#f59e0b', fontFamily: 'JetBrains Mono', fontWeight: 700 }}
            >
              Memoria del centro
            </p>
            <h2
              className="text-xl"
              style={{ fontFamily: 'Bebas Neue', color: '#f5f5f5', letterSpacing: '0.05em' }}
            >
              {center.name}
            </h2>
          </div>
          <button
            onClick={onClose}
            style={{ color: '#555', fontSize: '20px', lineHeight: 1 }}
            className="hover:text-white transition-colors"
          >
            ✕
          </button>
        </div>

        <div className="px-6 py-5 flex flex-col gap-3">
          <p className="text-xs" style={{ color: '#666', fontFamily: 'JetBrains Mono' }}>
            Incluye: equipamiento disponible, perfil de atletas, restricciones de espacio, estilo del coach, aforo habitual.
          </p>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={10}
            placeholder="Ej: Tenemos 2 remos, 1 ski erg, 8 barras olímpicas. Aforo habitual 10 personas. Muchos atletas con antecedentes de lesión lumbar..."
            className="w-full text-sm leading-relaxed"
            style={{
              fontFamily: 'JetBrains Mono',
              backgroundColor: '#141414',
              border: '1px solid #2c2c2c',
              borderRadius: '4px',
              color: '#e5e5e5',
              padding: '12px',
            }}
          />
        </div>

        <div
          className="flex gap-3 px-6 py-4 justify-end"
          style={{ borderTop: '1px solid #2c2c2c' }}
        >
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm transition-colors"
            style={{
              fontFamily: 'DM Sans',
              backgroundColor: 'transparent',
              border: '1px solid #2c2c2c',
              borderRadius: '4px',
              color: '#888',
            }}
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            className="px-5 py-2 text-sm font-semibold transition-colors hover:bg-amber-600"
            style={{
              fontFamily: 'DM Sans',
              backgroundColor: '#f59e0b',
              borderRadius: '4px',
              color: '#0c0c0c',
            }}
          >
            Guardar memoria
          </button>
        </div>
      </div>
    </div>
  )
}
