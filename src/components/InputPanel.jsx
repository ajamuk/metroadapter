const WORKOUT_PLACEHOLDER = `STRENGTH — 5x5 Back Squat @ 80%
Rest 2min between sets

AMRAP 12min:
5 Pull-ups
10 Push-ups
15 Air Squats

Score: rounds + reps`

export default function InputPanel({ center, workout, setWorkout, tempInstructions, setTempInstructions, onAdapt, loading }) {
  const disabled = !workout.trim() || loading

  return (
    <div
      className="flex flex-col h-full"
      style={{
        width: '42%',
        minWidth: '300px',
        backgroundColor: '#141414',
        borderRight: '1px solid #2c2c2c',
      }}
    >
      <div className="flex-1 flex flex-col min-h-0 p-4 pb-2">
        <label
          className="text-xs uppercase tracking-widest mb-2 block"
          style={{ fontFamily: 'JetBrains Mono', color: '#555', fontWeight: 700 }}
        >
          WOD Original
        </label>
        <textarea
          value={workout}
          onChange={(e) => setWorkout(e.target.value)}
          placeholder={WORKOUT_PLACEHOLDER}
          className="flex-1 w-full text-sm leading-relaxed"
          style={{
            fontFamily: 'JetBrains Mono',
            fontSize: '13px',
            backgroundColor: '#0c0c0c',
            border: '1px solid #2c2c2c',
            borderRadius: '4px',
            color: '#e5e5e5',
            padding: '12px',
            minHeight: 0,
          }}
        />
      </div>

      <div
        className="flex flex-col px-4 pt-2 pb-2"
        style={{ height: '160px', borderTop: '1px solid #2c2c2c' }}
      >
        <label
          className="text-xs uppercase tracking-widest mb-2 block"
          style={{ fontFamily: 'JetBrains Mono', color: '#555', fontWeight: 700 }}
        >
          Instrucciones puntuales (hoy)
        </label>
        <textarea
          value={tempInstructions}
          onChange={(e) => setTempInstructions(e.target.value)}
          placeholder="Ej: hay 3 atletas con lesión de hombro, el turf está ocupado hasta las 10h..."
          className="flex-1 w-full text-sm leading-relaxed"
          style={{
            fontFamily: 'DM Sans',
            fontSize: '13px',
            backgroundColor: '#0c0c0c',
            border: '1px solid #2c2c2c',
            borderRadius: '4px',
            color: '#e5e5e5',
            padding: '10px',
          }}
        />
      </div>

      <div className="px-4 pb-4 pt-2">
        <button
          onClick={onAdapt}
          disabled={disabled}
          className="w-full py-3 text-sm font-semibold tracking-wide transition-colors"
          style={{
            fontFamily: 'DM Sans',
            backgroundColor: disabled ? '#2a2a2a' : '#f59e0b',
            borderRadius: '4px',
            color: disabled ? '#555' : '#0c0c0c',
            cursor: disabled ? 'not-allowed' : 'pointer',
            border: 'none',
            letterSpacing: '0.03em',
          }}
        >
          {loading
            ? 'Adaptando…'
            : `⚡ Adaptar para ${center?.name ?? '—'}`}
        </button>
      </div>
    </div>
  )
}
