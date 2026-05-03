export default function CenterBar({ center, onOpenMemory }) {
  const hasMemory = Boolean(center?.memory)

  return (
    <div
      className="flex items-center justify-between px-6 py-3 flex-shrink-0"
      style={{
        backgroundColor: '#141414',
        borderBottom: '1px solid #2c2c2c',
        minHeight: '56px',
      }}
    >
      <div className="flex items-center gap-4">
        <h1
          style={{
            fontFamily: 'Bebas Neue',
            fontSize: '28px',
            color: '#f5f5f5',
            letterSpacing: '0.06em',
            lineHeight: 1,
          }}
        >
          {center?.name ?? '—'}
        </h1>
        <div className="flex items-center gap-2">
          <span
            style={{
              width: '8px',
              height: '8px',
              borderRadius: '50%',
              backgroundColor: hasMemory ? '#22c55e' : '#444',
              flexShrink: 0,
            }}
          />
          <span
            className="text-xs"
            style={{
              fontFamily: 'JetBrains Mono',
              color: hasMemory ? '#22c55e' : '#555',
            }}
          >
            {hasMemory ? 'Memoria configurada' : 'Sin memoria — configura el centro'}
          </span>
        </div>
      </div>

      <button
        onClick={onOpenMemory}
        className="text-xs px-3 py-1.5 transition-colors hover:border-amber-500 hover:text-amber-400"
        style={{
          fontFamily: 'DM Sans',
          backgroundColor: 'transparent',
          border: '1px solid #2c2c2c',
          borderRadius: '4px',
          color: '#888',
          cursor: 'pointer',
        }}
      >
        ✎ Memoria del centro
      </button>
    </div>
  )
}
