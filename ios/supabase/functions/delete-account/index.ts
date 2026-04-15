// Account deletion endpoint — required by App Store Guideline 5.1.1(v).
//
// Verifies the caller's JWT, then permanently deletes:
//   • All objects under {userId}/ in the `avatars` and `chat-media` buckets
//   • The user's rows in `device_tokens` (no FK cascade exists for this table)
//   • The auth.users row — which cascades to profiles, messages, and
//     message_reactions via existing ON DELETE CASCADE constraints.
//
// Deploy with: `supabase functions deploy delete-account`
// Requires env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto-set on Supabase).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405)
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? ""
    const token = authHeader.replace(/^Bearer\s+/i, "").trim()

    if (!token) {
      return jsonResponse({ error: "Missing bearer token" }, 401)
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("delete-account: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
      return jsonResponse({ error: "Server configuration error" }, 500)
    }

    const admin = createClient(supabaseUrl, serviceRoleKey)

    // 1. Verify the JWT and resolve the user
    const { data: userData, error: userError } = await admin.auth.getUser(token)
    if (userError || !userData?.user) {
      return jsonResponse({ error: "Invalid or expired session" }, 401)
    }

    const userId = userData.user.id

    // 2. Best-effort cleanup of storage prefixes (avatars + chat-media)
    await Promise.all([
      removePrefix(admin, "avatars", userId),
      removePrefix(admin, "chat-media", userId),
    ])

    // 3. Best-effort cleanup of rows that lack ON DELETE CASCADE
    const { error: tokenError } = await admin
      .from("device_tokens")
      .delete()
      .eq("user_id", userId)

    if (tokenError) {
      console.error("delete-account: device_tokens cleanup failed", tokenError)
      // non-fatal — proceed with auth deletion
    }

    // 4. Delete the auth user (cascades to profiles, messages, message_reactions)
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId)
    if (deleteError) {
      console.error("delete-account: auth.admin.deleteUser failed", deleteError)
      return jsonResponse({ error: "Failed to delete account. Please try again." }, 500)
    }

    return jsonResponse({ success: true })
  } catch (err) {
    console.error("delete-account: unexpected error", err)
    return jsonResponse({ error: (err as Error)?.message ?? "Unknown error" }, 500)
  }
})

// List every object under `${userId}/` in the bucket and remove them in batches.
async function removePrefix(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  userId: string,
): Promise<void> {
  try {
    const { data: objects, error } = await admin.storage
      .from(bucket)
      .list(userId, { limit: 1000 })

    if (error || !objects?.length) {
      return
    }

    const paths = objects.map((o: { name: string }) => `${userId}/${o.name}`)
    const { error: removeError } = await admin.storage.from(bucket).remove(paths)
    if (removeError) {
      console.error(`delete-account: failed to remove ${bucket}/${userId}/*`, removeError)
    }
  } catch (err) {
    console.error(`delete-account: storage cleanup error for ${bucket}`, err)
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
