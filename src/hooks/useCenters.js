import { useState, useEffect } from 'react'
import { DEFAULT_CENTERS } from '../lib/defaults'

const STORAGE_KEY = 'metro-centers-v2'

function loadCenters() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return JSON.parse(raw)
  } catch {}
  return DEFAULT_CENTERS
}

function saveCenters(centers) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(centers))
}

export function useCenters() {
  const [centers, setCenters] = useState(loadCenters)
  const [activeCenterId, setActiveCenterId] = useState(() => loadCenters()[0]?.id ?? null)

  useEffect(() => {
    saveCenters(centers)
  }, [centers])

  const activeCenter = centers.find((c) => c.id === activeCenterId) ?? centers[0] ?? null

  function addCenter(name) {
    const id = `center-${Date.now()}`
    const newCenter = { id, name: name.trim(), memory: '' }
    setCenters((prev) => [...prev, newCenter])
    setActiveCenterId(id)
    return newCenter
  }

  function updateMemory(centerId, memory) {
    setCenters((prev) =>
      prev.map((c) => (c.id === centerId ? { ...c, memory } : c))
    )
  }

  return { centers, activeCenter, activeCenterId, setActiveCenterId, addCenter, updateMemory }
}
