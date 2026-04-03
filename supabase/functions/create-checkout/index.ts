import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const PENDING_HOLD_MINUTES = 15;
const ACTIVE_PAYMENT_STATUSES = ["paid", "cash", "pending"] as const;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeName(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function isExpired(createdAt: string) {
  const created = new Date(createdAt).getTime();
  const expiresAt = created + PENDING_HOLD_MINUTES * 60 * 1000;
  return Number.isFinite(created) && Date.now() > expiresAt;
}

async function releaseExpiredPendingRSVPs(
  stripe: Stripe,
  supabase: ReturnType<typeof createClient>,
  sessionId: string,
) {
  const { data: stalePending, error } = await supabase
    .from("rsvps")
    .select("id, stripe_session_id, created_at")
    .eq("session_id", sessionId)
    .eq("payment_status", "pending");

  if (error || !stalePending?.length) {
    if (error) {
      console.error("Failed to load pending RSVPs for cleanup:", error);
    }
    return;
  }

  const expired = stalePending.filter((row) => isExpired(row.created_at));
  if (!expired.length) return;

  const stripeIds = expired
    .map((row) => row.stripe_session_id)
    .filter((value): value is string => Boolean(value));

  for (const paymentIntentId of stripeIds) {
    try {
      await stripe.paymentIntents.cancel(paymentIntentId);
    } catch (err) {
      console.error(`Failed to cancel stale PaymentIntent ${paymentIntentId}:`, err);
    }
  }

  const expiredIds = expired.map((row) => row.id);
  const { error: deleteError } = await supabase
    .from("rsvps")
    .delete()
    .in("id", expiredIds);

  if (deleteError) {
    console.error("Failed to delete expired pending RSVPs:", deleteError);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
      apiVersion: "2023-10-16",
    });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { session_id, player_name, player_email } = await req.json();
    const normalizedName = normalizeName(player_name ?? "");
    const normalizedEmail = normalizeEmail(player_email ?? "");

    if (!session_id || !normalizedName || !normalizedEmail) {
      return jsonResponse({ error: "Missing required fields" }, 400);
    }

    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("id, date, status, max_players, price_cents, payments_open")
      .eq("id", session_id)
      .single();

    if (sessionError || !session) {
      return jsonResponse({ error: "Session not found" }, 404);
    }

    if (session.status === "cancelled") {
      return jsonResponse({ error: "Session is cancelled" }, 400);
    }

    if (!session.payments_open) {
      return jsonResponse({ error: "Payments are not open yet" }, 400);
    }

    await releaseExpiredPendingRSVPs(stripe, supabase, session_id);

    const { data: existingRsvps, error: existingError } = await supabase
      .from("rsvps")
      .select("id, payment_status, created_at")
      .eq("session_id", session_id)
      .eq("player_email", normalizedEmail)
      .in("payment_status", [...ACTIVE_PAYMENT_STATUSES, "waitlist"]);

    if (existingError) {
      console.error("Failed to check existing RSVPs:", existingError);
      return jsonResponse({ error: "Unable to verify existing RSVP" }, 500);
    }

    const activeExisting = (existingRsvps ?? []).find((row) =>
      row.payment_status === "paid" || row.payment_status === "cash" ||
      (row.payment_status === "pending" && !isExpired(row.created_at))
    );

    if (activeExisting?.payment_status === "paid" || activeExisting?.payment_status === "cash") {
      return jsonResponse({ error: "You already have a confirmed spot" }, 400);
    }

    if (activeExisting?.payment_status === "pending") {
      return jsonResponse({
        error: "You already have a payment in progress. Finish it or wait a few minutes before trying again.",
      }, 400);
    }

    const { data: insertedRsvp, error: insertError } = await supabase
      .from("rsvps")
      .insert({
        session_id,
        player_name: normalizedName,
        player_email: normalizedEmail,
        payment_status: "pending",
      })
      .select("id, session_id, player_name, player_email, payment_status, stripe_session_id, created_at")
      .single();

    if (insertError || !insertedRsvp) {
      console.error("RSVP insert error:", insertError);
      return jsonResponse({ error: "Failed to create RSVP" }, 500);
    }

    const { data: activeReservations, error: reservationError } = await supabase
      .from("rsvps")
      .select("id, created_at")
      .eq("session_id", session_id)
      .in("payment_status", [...ACTIVE_PAYMENT_STATUSES])
      .order("created_at", { ascending: true })
      .order("id", { ascending: true });

    if (reservationError || !activeReservations) {
      await supabase.from("rsvps").delete().eq("id", insertedRsvp.id);
      console.error("Failed to verify reservation order:", reservationError);
      return jsonResponse({ error: "Failed to reserve spot" }, 500);
    }

    const reservationRank = activeReservations.findIndex((row) => row.id === insertedRsvp.id);
    if (reservationRank === -1 || reservationRank >= session.max_players) {
      await supabase.from("rsvps").delete().eq("id", insertedRsvp.id);
      return jsonResponse({ error: "Session is full" }, 400);
    }

    let paymentIntent: Stripe.PaymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.create({
        amount: session.price_cents,
        currency: "usd",
        automatic_payment_methods: { enabled: true },
        receipt_email: normalizedEmail,
        description: `RunsByIP — ${session.date}`,
        metadata: {
          session_id,
          rsvp_id: insertedRsvp.id,
          player_name: normalizedName,
          player_email: normalizedEmail,
        },
      });
    } catch (err) {
      await supabase.from("rsvps").delete().eq("id", insertedRsvp.id);
      console.error("PaymentIntent creation error:", err);
      return jsonResponse({ error: "Failed to start payment" }, 500);
    }

    const { error: updateError } = await supabase
      .from("rsvps")
      .update({ stripe_session_id: paymentIntent.id })
      .eq("id", insertedRsvp.id)
      .eq("payment_status", "pending");

    if (updateError) {
      console.error("Failed to attach PaymentIntent to RSVP:", updateError);
      try {
        await stripe.paymentIntents.cancel(paymentIntent.id);
      } catch (cancelErr) {
        console.error(`Failed to cancel PaymentIntent ${paymentIntent.id}:`, cancelErr);
      }
      await supabase.from("rsvps").delete().eq("id", insertedRsvp.id);
      return jsonResponse({ error: "Failed to start payment" }, 500);
    }

    return jsonResponse({ client_secret: paymentIntent.client_secret });
  } catch (err) {
    console.error("Error:", err);
    return jsonResponse({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});
