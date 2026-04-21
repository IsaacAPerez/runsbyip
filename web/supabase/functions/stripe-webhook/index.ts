import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";

// Single source of truth for RSVP row creation: we only insert when Stripe
// confirms a payment succeeded. No pending rows, no reconciliation.
// The PaymentIntent.metadata carries the session_id / player_name / player_email
// written by the create-checkout function.
Deno.serve(async (req: Request) => {
  try {
    const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
      apiVersion: "2023-10-16",
    });
    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

    const body = await req.text();
    const signature = req.headers.get("stripe-signature")!;

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        body,
        signature,
        webhookSecret,
      );
    } catch (err) {
      console.error(
        "Webhook signature verification failed:",
        err instanceof Error ? err.message : err,
      );
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 400,
      });
    }

    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event.data.object as Stripe.PaymentIntent;
      const { session_id, player_name, player_email } =
        paymentIntent.metadata ?? {};

      if (!session_id || !player_name || !player_email) {
        console.error(
          `PaymentIntent ${paymentIntent.id} missing required metadata`,
          paymentIntent.metadata,
        );
        // Acknowledge so Stripe stops retrying — nothing we can recover without metadata.
        return ack();
      }

      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );

      const { error } = await supabase.from("rsvps").insert({
        session_id,
        player_name,
        player_email,
        stripe_session_id: paymentIntent.id,
      });

      if (error) {
        // 23505 = unique_violation on stripe_session_id. Webhook retried for an RSVP
        // we already wrote — treat as success so Stripe stops retrying.
        if ((error as { code?: string }).code === "23505") {
          console.log(
            `RSVP for PaymentIntent ${paymentIntent.id} already exists — duplicate webhook`,
          );
          return ack();
        }

        console.error("Failed to insert RSVP:", error);
        return new Response(
          JSON.stringify({ error: "Database insert failed" }),
          { status: 500 },
        );
      }

      console.log(`RSVP created for PaymentIntent ${paymentIntent.id}`);
    }

    return ack();
  } catch (err) {
    console.error("Webhook error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "unknown" }),
      { status: 500 },
    );
  }
});

function ack(): Response {
  return new Response(JSON.stringify({ received: true }), {
    headers: { "Content-Type": "application/json" },
  });
}
