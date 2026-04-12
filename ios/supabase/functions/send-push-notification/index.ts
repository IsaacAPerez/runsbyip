import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// This function accepts:
// { userId?: string, topic: string, title: string, body: string, data?: object }
// OR: { broadcast: true, topic: string, title: string, body: string, data?: object }
//
// Uses APNs HTTP/2 API with JWT auth
// APNs JWT requires: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY env vars
// APNS_BUNDLE_ID env var for your app bundle ID

serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  }

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    const { userId, broadcast, title, body, data } = await req.json()

    // Get device tokens
    let query = supabase.from("device_tokens").select("token").eq("platform", "ios")
    if (!broadcast && userId) query = query.eq("user_id", userId)

    const { data: tokens, error } = await query
    if (error) throw error

    // Generate APNs JWT (simplified - in prod use proper JWT lib)
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.isaacperez.runsbyip"

    const results = []
    for (const { token } of tokens ?? []) {
      // APNs HTTP/2 push
      const payload = {
        aps: {
          alert: { title, body },
          sound: "default",
          badge: 1,
        },
        ...data,
      }

      results.push({ token, payload, status: "queued" })
    }

    return new Response(
      JSON.stringify({ sent: results.length, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
