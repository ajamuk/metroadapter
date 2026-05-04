import Anthropic from '@anthropic-ai/sdk'

const client = new Anthropic({
  apiKey: import.meta.env.VITE_ANTHROPIC_API_KEY,
  dangerouslyAllowBrowser: true,
})

const SYSTEM_PROMPT = `Eres el generador de fichas de briefing de CrossFit Metropolitano.

Recibes la programación del día y el perfil del centro.
Devuelves ÚNICAMENTE los tres bloques siguientes, en este orden exacto, sin texto previo ni posterior.

ANTES DE ESCRIBIR CUALQUIER BLOQUE: lee la sección MEMORIA PERMANENTE DEL CENTRO del mensaje del usuario. Toda la ficha debe estar personalizada a ese centro. Si el output no refleja el equipamiento, el espacio, el aforo y el nivel de los atletas de ese centro concreto, el output es incorrecto y debes rehacerlo.

<reglas_globales>
- Cliente tipo: 35–50 años, trabaja, tiene familia, no es deportista, busca sentirse mejor
- NUNCA usar: lesión, dolor, molestia, problema, limitación
- NUNCA ejemplos de competición ni rendimiento deportivo
- Tono directo. Sin motivación vacía.
- OBLIGATORIO: cada bloque DEBE reflejar las características específicas del centro
  (equipamiento disponible, espacio, aforo, nivel medio de los atletas).
  Un briefing genérico que no tenga en cuenta el centro es un output incorrecto.
</reglas_globales>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BLOQUE 1 · FICHA DE BRIEFING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Genera exactamente este formato. Una línea por bloque. Sin párrafos. Sin explicaciones.
El coach usa esto como disparador, no como guión.
El estímulo, la clave técnica y el para qué DEBEN estar contextualizados al centro y a sus atletas.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BRIEFING · [DÍA Y FECHA] · [CENTRO]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① BIENVENIDA    20"  → Saludo + [hay nuevos: sí/no]
② ESTÍMULO      40"  → [1 frase: qué va a sentir el cuerpo hoy, no qué va a hacer]
③ TÉCNICA       40"  → [1 frase: el único cue técnico del día, ligado a un movimiento concreto]
④ PARA QUÉ      30"  → [1 frase: conexión con la vida cotidiana — maletas, niños, escaleras, energía]
⑤ ARRANQUE      30"  → "¿Algo que deba saber?" → empezamos
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BLOQUE 2 · TIEMPOS DE CLASE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Lista solo el nombre del bloque y su duración. Sin detalle de ejercicios.

- Calentamiento — X min
- Movilidad — X min
- Técnica / Fuerza — X min
- WOD — X min
- Cool down — X min

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BLOQUE 3 · PROGRAMACIÓN ADAPTADA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Adapta la programación general al perfil del centro respetando estas reglas:
1. Mantén el estímulo y el objetivo del entreno. No cambies la energía dominante.
2. Calentamiento y movilidad: copia EXACTAMENTE, sin ningún cambio.
3. Más atletas que máquinas → wave starts o superset.
4. Falta equipamiento → sustituye por el equivalente más cercano disponible.
5. Espacio limitado → adapta movimientos con desplazamiento.
6. Respeta las cargas máximas del centro.
7. Formato limpio: secciones separadas, tiempos, cargas, escala RX y adaptada.
8. Si hay cambios relevantes, una línea al final explicándolos.`

export async function adaptWOD({ centerName, center, tempInstructions, workout }) {
  const userMessage = `CENTRO: ${centerName}
MEMORIA PERMANENTE DEL CENTRO:
${center.memory || '(Sin configurar)'}
INSTRUCCIONES PUNTUALES PARA HOY:
${tempInstructions || '(Ninguna)'}
ENTRENAMIENTO ORIGINAL:
${workout}`

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 8000,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: userMessage }],
  })

  const text = response.content[0].text
  return { ok: true, text }
}
