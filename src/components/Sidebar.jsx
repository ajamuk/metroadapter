import { useState, useRef, useEffect } from 'react'

export default function Sidebar({ centers, activeCenterId, onSelectCenter, onAddCenter, onOpenMemory }) {
  const [adding, setAdding] = useState(false)
  const [newName, setNewName] = useState('')
  const inputRef = useRef(null)

  useEffect(() => {
    if (adding && inputRef.current) inputRef.current.focus()
  }, [adding])

  function handleKeyDown(e) {
    if (e.key === 'Enter') {
      const name = newName.trim()
      if (name) {
        onAddCenter(name)
        setNewName('')
        setAdding(false)
      }
    }
    if (e.key === 'Escape') {
      setNewName('')
      setAdding(false)
    }
  }

  return (
    <aside
      className="flex flex-col h-full flex-shrink-0"
      style={{
        width: '220px',
        backgroundColor: '#141414',
        borderRight: '1px solid #2c2c2c',
      }}
    >
      <div className="px-4 py-5" style={{ borderBottom: '1px solid #2c2c2c' }}>
        <div style={{ fontFamily: 'Bebas Neue', fontSize: '22px', letterSpacing: '0.05em', lineHeight: 1.1 }}>
          <span style={{ color: '#f59e0b' }}>METRO</span>
          <span style={{ color: '#555' }}> WOD ADAPTER</span>
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto py-2">
        {centers.map((center) => {
          const isActive = center.id === activeCenterId
          return (
            <button
              key={center.id}
              onClick={() => onSelectCenter(center.id)}
              className="w-full flex items-center gap-2 px-4 py-2.5 text-left transition-colors"
              style={{
                backgroundColor: isActive ? 'rgba(245,158,11,0.07)' : 'transparent',
                borderLeft: isActive ? '2px solid #f59e0b' : '2px solid transparent',
                cursor: 'pointer',
              }}
            >
              <span
                style={{
                  width: '7px',
                  height: '7px',
                  borderRadius: '50%',
                  backgroundColor: isActive ? '#f59e0b' : '#444',
                  flexShrink: 0,
                }}
              />
              <span
                className="flex-1 text-sm truncate"
                style={{
                  fontFamily: 'DM Sans',
                  color: isActive ? '#f5f5f5' : '#888',
                  fontWeight: isActive ? 600 : 400,
                }}
              >
                {center.name}
              </span>
              {center.memory && (
                <span
                  title="Memoria configurada"
                  style={{
                    width: '6px',
                    height: '6px',
                    borderRadius: '50%',
                    backgroundColor: '#22c55e',
                    flexShrink: 0,
                  }}
                />
              )}
            </button>
          )
        })}
      </nav>

      <div className="p-3" style={{ borderTop: '1px solid #2c2c2c' }}>
        {adding ? (
          <input
            ref={inputRef}
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Nombre del centro…"
            className="w-full text-sm px-3 py-2"
            style={{
              fontFamily: 'DM Sans',
              backgroundColor: '#0c0c0c',
              border: '1px solid #f59e0b',
              borderRadius: '4px',
              color: '#f5f5f5',
              outline: 'none',
            }}
          />
        ) : (
          <button
            onClick={() => setAdding(true)}
            className="w-full text-sm py-2 transition-colors hover:text-amber-400"
            style={{
              fontFamily: 'DM Sans',
              backgroundColor: 'transparent',
              border: '1px solid #2c2c2c',
              borderRadius: '4px',
              color: '#666',
              cursor: 'pointer',
            }}
          >
            + Añadir centro
          </button>
        )}
      </div>
    </aside>
  )
}
