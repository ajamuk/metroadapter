import { useState } from 'react'

export default function OutputSection({ title, tag, content, mono, defaultOpen }) {
  const [open, setOpen] = useState(defaultOpen)
  const [copied, setCopied] = useState(false)

  function handleCopy() {
    navigator.clipboard.writeText(content).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <div
      style={{
        backgroundColor: '#1c1c1c',
        border: '1px solid #2c2c2c',
        borderRadius: '4px',
        overflow: 'hidden',
      }}
    >
      <div
        className="flex items-center justify-between px-4 py-2.5 cursor-pointer select-none"
        style={{ borderBottom: open ? '1px solid #2c2c2c' : 'none' }}
        onClick={() => setOpen((v) => !v)}
      >
        <div className="flex items-center gap-3">
          <span
            className="text-xs px-2 py-0.5"
            style={{
              fontFamily: 'JetBrains Mono',
              fontSize: '10px',
              backgroundColor: '#2c2c2c',
              color: '#f59e0b',
              borderRadius: '2px',
              fontWeight: 700,
              letterSpacing: '0.08em',
            }}
          >
            {tag}
          </span>
          <span
            className="text-sm font-medium"
            style={{ fontFamily: 'DM Sans', color: '#d4d4d4' }}
          >
            {title}
          </span>
        </div>
        <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={handleCopy}
            className="text-xs px-2.5 py-1 transition-colors"
            style={{
              fontFamily: 'DM Sans',
              backgroundColor: 'transparent',
              border: '1px solid #2c2c2c',
              borderRadius: '4px',
              color: copied ? '#22c55e' : '#666',
              cursor: 'pointer',
            }}
          >
            {copied ? 'Copiado' : 'Copiar'}
          </button>
          <span style={{ color: '#444', fontSize: '12px' }}>{open ? '▲' : '▼'}</span>
        </div>
      </div>

      {open && (
        <div className="px-4 py-4">
          <pre
            className="text-sm leading-relaxed whitespace-pre-wrap break-words"
            style={{
              fontFamily: mono ? 'JetBrains Mono' : 'DM Sans',
              fontSize: mono ? '12px' : '13px',
              color: '#d4d4d4',
              margin: 0,
            }}
          >
            {content}
          </pre>
        </div>
      )}
    </div>
  )
}
