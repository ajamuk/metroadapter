import Anthropic from '@anthropic-ai/sdk'

const client = new Anthropic({
  apiKey: import.meta.env.VITE_ANTHROPIC_API_KEY,
  dangerouslyAllowBrowser: true,
})

const SYSTEM_PROMPT =
  'Eres el adaptador de entrenamientos de CrossFit Metropolitano. Adaptas WODs al contexto específico de cada centro. Responde ÚNICAMENTE con un JSON válido, sin markdown, sin backticks, sin texto antes ni después: {"workout_adaptado": "...","pasos_briefing": "...","resound_plan_parte1": "...","resound_plan_parte2": "..."}'

// Fixes literal newlines/tabs inside JSON string values
function fixLiteralControlChars(str) {
  let result = ''
  let inString = false
  let escaped = false
  for (let i = 0; i < str.length; i++) {
    const ch = str[i]
    if (escaped) {
      result += ch
      escaped = false
    } else if (ch === '\\' && inString) {
      result += ch
      escaped = true
    } else if (ch === '"') {
      inString = !inString
      result += ch
    } else if (inString && ch === '\n') {
      result += '\\n'
    } else if (inString && ch === '\r') {
      result += '\\r'
    } else if (inString && ch === '\t') {
      result += '\\t'
    } else {
      result += ch
    }
  }
  return result
}

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
    max_tokens: 8000,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: userMessage }],
  })

  const raw = response.content[0].text
  const jsonMatch = raw.match(/\{[\s\S]*\}/)
  const toParse = jsonMatch ? jsonMatch[0] : raw
  const repaired = fixLiteralControlChars(toParse)
  try {
    return { ok: true, data: JSON.parse(repaired) }
  } catch (e) {
    return { ok: false, raw: `Parse error: ${e.message}\n\n--- RAW RESPONSE ---\n${raw}` }
  }
}
