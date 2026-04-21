import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Creates a Stripe PaymentIntent for an RSVP.
// We do NOT insert into the rsvps table here — the stripe-webhook function
// is the sole creator of RSVP rows, triggered by payment_intent.succeeded.
// All the data the webhook needs is carried in PaymentIntent.metadata.
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

    if (!session_id || !player_name || !player_email) {
      return json({ error: "Missing required fields" }, 400);
    }

    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("id, status, payments_open, price_cents, max_players, date")
      .eq("id", session_id)
      .single();

    if (sessionError || !session) {
      return json({ error: "Session not found" }, 404);
    }

    if (session.status === "cancelled") {
      return json({ error: "Session is cancelled" }, 400);
    }

    if (!session.payments_open) {
      return json({ error: "Payments are not open yet" }, 400);
    }

    const { count } = await supabase
      .from("rsvps")
      .select("*", { count: "exact", head: true })
      .eq("session_id", session_id);

    if (count !== null && count >= session.max_players) {
      return json({ error: "Session is full" }, 400);
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: session.price_cents,
      currency: "usd",
      automatic_payment_methods: { enabled: true },
      receipt_email: player_email,
      description: `RunsByIP \u2014 ${session.date}`,
      metadata: {
        session_id,
        player_name,
        player_email,
      },
    });

    return json({ client_secret: paymentIntent.client_secret });
  } catch (err) {
    console.error("create-checkout error:", err);
    return json({ error: err instanceof Error ? err.message : "unknown" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
