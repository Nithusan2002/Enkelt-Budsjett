import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const jsonHeaders = {
  "Content-Type": "application/json",
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: jsonHeaders,
    })
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  const authorization = req.headers.get("Authorization")

  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "Function is not configured" }), {
      status: 500,
      headers: jsonHeaders,
    })
  }

  if (!authorization?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Missing bearer token" }), {
      status: 401,
      headers: jsonHeaders,
    })
  }

  const jwt = authorization.replace("Bearer ", "").trim()
  const supabase = createClient(supabaseUrl, serviceRoleKey)

  const { data: userData, error: userError } = await supabase.auth.getUser(jwt)
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    })
  }

  const { error: deleteError } = await supabase.auth.admin.deleteUser(userData.user.id)
  if (deleteError) {
    return new Response(JSON.stringify({ error: deleteError.message }), {
      status: 500,
      headers: jsonHeaders,
    })
  }

  return new Response(null, { status: 204, headers: jsonHeaders })
})
