import Anthropic from '@anthropic-ai/sdk'

const client = new Anthropic({
  apiKey: import.meta.env.VITE_ANTHROPIC_API_KEY,
  dangerouslyAllowBrowser: true,
})

const SYSTEM_PROMPT =
  'Eres el adaptador de entrenamientos de CrossFit Metropolitano. Adaptas WODs al contexto específico de cada centro. Responde ÚNICAMENTE con un JSON válido, sin markdown, sin backticks, sin texto antes ni después: {"workout_adaptado": "...","pasos_briefing": "...","resound_plan_parte1": "...","resound_plan_parte2": "..."}'

export async function adaptWOD({ centerName, center, tempInstructions, workout }) {
  const userMessage = `CENTRO: ${centerName}
MEMORIA PERMANENTE DEL CENTRO:
${center.memory || '(Sin configurar)'}
INSTRUCCIONES PUNTUALES PARA HOY:
${tempInstructions || '(Ninguna)'}
ENTRENAMIENTO ORIGINAL:
${workout}`

  const response = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 4000,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: userMessage }],
  })

  const raw = response.content[0].text
  const jsonMatch = raw.match(/\{[\s\S]*\}/)
  const toParse = jsonMatch ? jsonMatch[0] : raw
  try {
    return { ok: true, data: JSON.parse(toParse) }
  } catch {
    return { ok: false, raw }
  }
}
