import "@supabase/functions-js/edge-runtime.d.ts"

const jsonHeaders = {
  "Content-Type": "application/json",
}

type CategorySummary = {
  title: string
  amount: number
}

type GoalSummary = {
  progress: number
  monthlyNeed: number
}

type InsightPayload = {
  income: number
  spent: number
  remaining: number
  fixedItemsTotal: number
  topCategories: CategorySummary[]
  goal?: GoalSummary | null
}

type InsightResponse = {
  summary: string
  keyDriver: string
  nextStep: string
}

function fallbackResponse(payload: InsightPayload): InsightResponse {
  const remaining = Math.round(payload.remaining)
  const fixedItems = Math.round(payload.fixedItemsTotal)
  const biggestCategory = payload.topCategories[0]?.title ?? "utgiftene"

  return {
    summary: `AI-hjelperen er midlertidig slått av. Du har ${remaining} kr igjen denne måneden basert på tallene som er registrert.`,
    keyDriver: `${biggestCategory} og faste poster på ${fixedItems} kr ser ut til å påvirke måneden mest akkurat nå.`,
    nextStep: "Se over de største utgiftene først hvis du vil justere resten av måneden uten å bruke AI.",
  }
}

function badRequest(message: string, status = 400) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: jsonHeaders,
  })
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return badRequest("Method not allowed", 405)
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY")
  if (!apiKey) {
    return badRequest("Function is not configured", 500)
  }

  let payload: InsightPayload
  try {
    payload = await req.json()
  } catch {
    return badRequest("Invalid JSON")
  }

  const aiInsightsEnabled = (Deno.env.get("AI_INSIGHTS_ENABLED") ?? "false").toLowerCase() === "true"
  if (!aiInsightsEnabled) {
    return new Response(JSON.stringify(fallbackResponse(payload)), {
      status: 200,
      headers: jsonHeaders,
    })
  }

  const prompt = [
    "Du er en rolig hjelper i en norsk budsjettapp.",
    "Skriv kort på norsk.",
    "Ikke gi investeringsråd eller finansiell rådgivning.",
    "Returner kun gyldig JSON med feltene summary, keyDriver og nextStep.",
    "Oppsummer måneden kort, si hva som påvirker mest, og foreslå ett enkelt neste steg.",
    `Inntekt: ${Math.round(payload.income)}`,
    `Brukt hittil: ${Math.round(payload.spent)}`,
    `Igjen denne måneden: ${Math.round(payload.remaining)}`,
    `Faste poster totalt: ${Math.round(payload.fixedItemsTotal)}`,
    `Toppkategorier: ${payload.topCategories.map((item) => `${item.title} (${Math.round(item.amount)})`).join(", ") || "Ingen"}`,
    payload.goal
      ? `Målstatus: progresjon ${Math.round(payload.goal.progress * 100)} prosent, behov per måned ${Math.round(payload.goal.monthlyNeed)}`
      : "Målstatus: Ingen aktiv målstatus",
  ].join("\n")

  const openAIResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_MODEL") ?? "gpt-4.1-nano",
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "Du forklarer månedlige økonomitall på norsk. Vær konkret, rolig og kort. Ingen hype. Ingen investeringsråd.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.4,
    }),
  })

  if (!openAIResponse.ok) {
    const errorText = await openAIResponse.text()
    return badRequest(errorText || "OpenAI request failed", 502)
  }

  const completion = await openAIResponse.json()
  const rawContent = completion?.choices?.[0]?.message?.content

  if (typeof rawContent !== "string" || rawContent.trim().length === 0) {
    return badRequest("Invalid AI response", 502)
  }

  let parsed: InsightResponse
  try {
    parsed = JSON.parse(rawContent)
  } catch {
    return badRequest("AI response was not valid JSON", 502)
  }

  return new Response(JSON.stringify(parsed), {
    status: 200,
    headers: jsonHeaders,
  })
})
