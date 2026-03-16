import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Get session details
    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("*")
      .eq("id", session_id)
      .single();

    if (sessionError || !session) {
      return new Response(JSON.stringify({ error: "Session not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (session.status === "cancelled") {
      return new Response(JSON.stringify({ error: "Session is cancelled" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check if session is full
    const { count } = await supabase
      .from("rsvps")
      .select("*", { count: "exact", head: true })
      .eq("session_id", session_id)
      .in("payment_status", ["paid", "cash"]);

    if (count !== null && count >= session.max_players) {
      return new Response(JSON.stringify({ error: "Session is full" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Determine success URL base from Origin or Referer header
    const origin =
      req.headers.get("origin") ||
      req.headers.get("referer")?.replace(/\/[^/]*$/, "") ||
      "https://example.com";

    // Create Stripe Checkout session
    const checkoutSession = await stripe.checkout.sessions.create({
      payment_method_types: ["card"],
      mode: "payment",
      line_items: [
        {
          price_data: {
            currency: "usd",
            product_data: {
              name: `Wednesday Hoops — ${session.date}`,
              description: `${session.time} at ${session.location}`,
            },
            unit_amount: session.price_cents,
          },
          quantity: 1,
        },
      ],
      customer_email: player_email,
      success_url: `${origin}/success.html`,
      cancel_url: `${origin}/index.html`,
      metadata: {
        session_id,
        player_name,
        player_email,
      },
    });

    // Create RSVP record
    const { error: rsvpError } = await supabase.from("rsvps").insert({
      session_id,
      player_name,
      player_email,
      payment_status: "pending",
      stripe_session_id: checkoutSession.id,
    });

    if (rsvpError) {
      console.error("RSVP insert error:", rsvpError);
      return new Response(
        JSON.stringify({ error: "Failed to create RSVP" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ checkout_url: checkoutSession.url }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("Error:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  }
});
