import { useState } from 'react'
import { useCenters } from './hooks/useCenters'
import { adaptWOD } from './lib/anthropic'
import Sidebar from './components/Sidebar'
import CenterBar from './components/CenterBar'
import InputPanel from './components/InputPanel'
import OutputPanel from './components/OutputPanel'
import MemoryModal from './components/MemoryModal'

export default function App() {
  const { centers, activeCenter, activeCenterId, setActiveCenterId, addCenter, updateMemory } = useCenters()

  const [workout, setWorkout] = useState('')
  const [tempInstructions, setTempInstructions] = useState('')
  const [outputState, setOutputState] = useState({ status: 'idle', data: null, rawError: null })
  const [memoryModalOpen, setMemoryModalOpen] = useState(false)

  function handleSelectCenter(id) {
    setActiveCenterId(id)
    setOutputState({ status: 'idle', data: null, rawError: null })
  }

  function handleAddCenter(name) {
    addCenter(name)
    setMemoryModalOpen(true)
  }

  async function handleAdapt() {
    if (!workout.trim() || outputState.status === 'loading') return
    setOutputState({ status: 'loading', data: null, rawError: null })
    try {
      const result = await adaptWOD({
        centerName: activeCenter.name,
        center: activeCenter,
        tempInstructions,
        workout,
      })
      if (result.ok) {
        setOutputState({ status: 'done', data: result.data, rawError: null })
      } else {
        setOutputState({ status: 'error', data: null, rawError: result.raw })
      }
    } catch (err) {
      setOutputState({ status: 'error', data: null, rawError: err?.message ?? String(err) })
    }
  }

  return (
    <div
      className="flex h-screen overflow-hidden"
      style={{ backgroundColor: '#0c0c0c' }}
    >
      <Sidebar
        centers={centers}
        activeCenterId={activeCenterId}
        onSelectCenter={handleSelectCenter}
        onAddCenter={handleAddCenter}
        onOpenMemory={() => setMemoryModalOpen(true)}
      />

      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <CenterBar
          center={activeCenter}
          onOpenMemory={() => setMemoryModalOpen(true)}
        />

        <div className="flex flex-1 min-h-0 overflow-hidden">
          <InputPanel
            center={activeCenter}
            workout={workout}
            setWorkout={setWorkout}
            tempInstructions={tempInstructions}
            setTempInstructions={setTempInstructions}
            onAdapt={handleAdapt}
            loading={outputState.status === 'loading'}
          />
          <OutputPanel
            center={activeCenter}
            state={outputState}
          />
        </div>
      </div>

      {memoryModalOpen && activeCenter && (
        <MemoryModal
          center={activeCenter}
          onSave={updateMemory}
          onClose={() => setMemoryModalOpen(false)}
        />
      )}
    </div>
  )
}
